#!/usr/sbin/env bash

set -exuo pipefail

# load config file
# shellcheck source=/home/vahit/.config/itsok.conf
source "${HOME}"/.config/itsok.conf

BACKUP_PREFIX=${BACKUP_PREFIX:-$(date +"%Y-%m-%d")}
LOG_FILE=${LOG_FILE:-"/var/log/itsok.log"}
MYSQL_DATADIR=$(grep -i datadir /etc/mysql/my.cnf | awk '{print $3}')
if [[ -z $MYSQL_DATADIR ]]; then
    MYSQL_DATADIR=$(grep -i datadir /etc/mysql/my.cnf | cut -f2 -d"=")
fi

# FLAG is a boolean variable and show process final status.
# Default is True
FLAG="true"

# truncate log file
cat  /dev/null > "${LOG_FILE}"

REPORT_FILE=$(dirname "${0}")"/report.txt"
cat /dev/null > "${REPORT_FILE}"
DATE=$(date)
echo "DataBase backup files health check process start at ${DATE}" > "${REPORT_FILE}"
echo "Below list show that process steps status:" >> "${REPORT_FILE}"

# mysqld bin file full path
MYSQLD="mysqld"

function send_report() {
    if [[ ${FLAG} == "true" ]]; then
        SUBJECT="[HEALTHY] Today DB backup files"
    else
        SUBJECT="[Faulty] Today DB backup files"
    fi
    if [ ! -s "${LOG_FILE}" ]; then
	EMAIL="Dr.Backup <no-reply@clickyab.com>" mutt -s "${SUBJECT}" -- sysadmin@clickyab.com < "${REPORT_FILE}"
    else
	EMAIL="Dr.Backup <no-reply@clickyab.com>" mutt -s "${SUBJECT}" -a "${LOG_FILE}" -- sysadmin@clickyab.com < "${REPORT_FILE}"
    fi
    exit 0
}

if [[ -z ${BACKUPS_DIR} ]]; then
    echo "[x] Backups directory" >> "${REPORT_FILE}"
    echo -e "$(date +'%F %T') backups directory not specified!" >> "${LOG_FILE}"
    FLAG="false"
    send_report
fi

function mysql_service(){
    command=${1:-stop}
    case $command in
        start)
            OUTPUT=$(systemctl restart mysql)
            RETURN_CODE=${?}
            if [[ ${RETURN_CODE} -ne 0 ]]; then
                echo "[x] Start MySQL" >> "${REPORT_FILE}"
                echo "${OUTPUT}" >> "${LOG_FILE}"
            else
                echo "[✓] Start MySQL" >> "${REPORT_FILE}"
            fi
            ;;
        stop)
            OUTPUT=$(pgrep "${MYSQLD}" | awk '{print $1}')
            RETURN_CODE=${?}
            if [[ -z ${OUTPUT} && ${RETURN_CODE} -eq 0 ]]; then
                echo "[✓] Stop MySQL Service" >> "${REPORT_FILE}"
            elif [[ ! -z ${OUTPUT} && ${RETURN_CODE} -eq 0 ]]; then
                OUTPUT=$(systemctl stop mysql)
                RETURN_CODE=${?}
                if [[ ${RETURN_CODE} -eq 0 ]]; then
                    echo "[✓] Stop MySQL Service" >> "${REPORT_FILE}"
                else
                    echo "[x] Stop MySQL Service" >> "${REPORT_FILE}"
                    echo "${OUTPUT}" >> "${LOG_FILE}"
                    FLAG="false"
                    send_report
                fi
            else
                echo "[x] Stop MySQL Service" >> "${REPORT_FILE}"
                echo "${OUTPUT}" >> "${LOG_FILE}"
                FLAG="false"
                send_report
            fi
            ;;
    esac
}

# select test file
TODAY_FILE=$(ls -1t "${BACKUPS_DIR}" | grep "^${BACKUP_PREFIX}" | head --lines=1)
if [[ -z ${TODAY_FILE} ]]; then
    echo "[x] File Selection" >> "${REPORT_FILE}"
else
    echo "[✓] File Selection" >> "${REPORT_FILE}"
fi

# stop mysqld service if it's running.
mysql_service stop

# empty MySQL datadir directory
OUTPUT=$(rm -r ${MYSQL_DATADIR})
RETURN_CODE=${?}
if [[ ${RETURN_CODE} -ne 0 ]]; then
    echo "[x] Remove MySQL datadir" >> "${REPORT_FILE}"
    echo "${OUTPUT}" >> "${LOG_FILE}"
else
    echo "[✓] Remove MySQL datadir" >> "${REPORT_FILE}"
fi

# restore DB file
OUTPUT=$(innobackupex --copy-back "${BACKUPS_DIR}"/"${TODAY_FILE}" 2>&1)
RETURN_CODE=${?}
if [[ ${RETURN_CODE} -eq 0 ]]; then
    if [[ $(echo "${OUTPUT}" | tail --lines=1 | grep -oE ".{13}$") == "completed OK!" ]]; then
        echo "[✓] Restore backup" >> "${REPORT_FILE}"
    else
        echo "[x] Restore backup" >> "${REPORT_FILE}"
        echo -e "${OUTPUT}" >> "${LOG_FILE}"
    fi
else
    echo "[x] Restore backup" >> "${REPORT_FILE}"
    echo -e "${OUTPUT}" >> "${LOG_FILE}"
fi

# correct MySQL datadir permissions
OUTPUT=$(chown -R mysql:mysql ${MYSQL_DATADIR})
RETURN_CODE=${?}
if [[ ${RETURN_CODE} -ne 0 ]]; then
    echo "[x] Correct MySQL datadir permissions" >> "${REPORT_FILE}"
    echo "${OUTPUT}" >> "${LOG_FILE}"
else
    echo "[✓] Correct MySQL datadir permissons" >> "${REPORT_FILE}"
fi

# start MySQL service
mysql_service start

send_report
