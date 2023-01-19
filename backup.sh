#!/bin/bash

# Скрипт для резервного копирования баз данных и файлов
# ver 1.2

# ==================================== ENV ==============================================

# Файл с данными для подлкючения к mysql server ( для опции --defaults-extra-file)
# https://dev.mysql.com/doc/refman/8.0/en/option-file-options.html#option_general_defaults-extra-file
# Данное подключение используется по умолчанию, если ничего не указано подключюение идет по логину и паролю
MYSQL_CONNECT_FILES="/quicklaunch/my.cnf"
# Данны для подключения к mysql server
MYSQL_USER="mighty"
MYSQL_PASSWORD="{{ mighty_mysql_pass }}"
MYSQL_PORT="3306"
MYSQL_HOST="{{ db_host }}"


# Список баз данных для которых не нужно делать резервную копию
IGNORE_DB="performance_schema information_schema sys tmp"
# Какие таблицы не включать в рзеревную копию (запись вида: db.table через пробел)
IGNORE_TABLES=""
# Таблицы для которых копирутся только структура, без данных (только имя таблицы через пробел)
IGNORE_DATA_TABLE=""

# Директория сайта
SITE_FILES="/home/www"

# Директория для хранения резервных копий
BACKUPDIR="/usr/backups"

# Время хранения ежедневных бекапов
STOR_DAY_BACKUPS="10"
# Время хранения ежемесячных бекапов (количество месяцев)
STOR_MON_BACKUPS="6"
# День месяца когда нужно делать ежемесяцчный бекап (если оставить пустым, ежемесячные бекапы не будут делаться)
BACKUP_MONTHLY_DAY="01"

# Тип сжатия (gzip или bzip2)
COMPRESS_BACKUP="gzip"

# Опиции для mysqldump
MYSQLDUMP_OPT="--single-transaction --triggers --routines --compress"

# directories for backups mysql
BACKUPDIR_DB="${BACKUPDIR}/db"
BACKUPDIR_DB_DAILY="${BACKUPDIR_DB}/daily"
BACKUPDIR_DB_MONTHLY="${BACKUPDIR_DB}/monthly"
# directories for backups files
BACKUPDIR_FILES="${BACKUPDIR}/files"
BACKUPDIR_FILES_DAILY="${BACKUPDIR_FILES}/daily"
BACKUPDIR_FILES_MONTHLY="${BACKUPDIR_FILES}/monthly"

# ================================ loging =============================================

if [ "s"${TBASHLOG__} = "s" ] ; then
    TBASHLOG__="./backup.log"
fi

if [ ! ${TEEBASH__} ] ; then
    TEEBASH__=1
    . $0 "$@" | tee -a ${TBASHLOG__}
    exit $?
fi

# ================================ Functions ===========================================


# Функция для резервного копирования баз данных
dbdump () {
    mysqldump $MYSQL_LOGIN $MYSQLDUMP_OPT --no-data $1 > $2
    mysqldump $MYSQL_LOGIN $MYSQLDUMP_OPT $OPT_DATA $1 >> $2  
    return 0
}

# Функция для сжатия
compression () {
if [ "$COMPRESS_BACKUP" = "gzip" ]; then
    if [ -d "$1" ] ; then
       fileName=`basename $1`
       cd "$1" && tar czf "$2/$fileName.tar.gz" .
       echo
       echo Backup Information for "$2/$fileName.tar.gz"
       gzip -l "$2/$fileName.tar.gz"
    else
       gzip -f "$1"
       echo
       echo Backup Information for "$1"
       gzip -l "$1.gz"
    fi
elif [ "$COMPRESS_BACKUP" = "bzip2" ]; then
    if [ -d "$1" ] ; then
       fileName=`basename $1`
       cd "$1" && tar cjvf "$2/$fileName.tar.bz2" .
    else
       echo Compression information for "$1.bz2"
       bzip2 -f -v $1 2>&1
    fi
else
    echo "No compression option set, check advanced settings"
fi
return 0
}

# ================================ Run script ===========================================

# Создание директорий для резервных копий если их нет
[ -d $BACKUPDIR_DB ] || mkdir -p $BACKUPDIR_DB
[ -d $BACKUPDIR_DB_DAILY ] || mkdir -p $BACKUPDIR_DB_DAILY
[ -d $BACKUPDIR_DB_MONTHLY ] || mkdir -p $BACKUPDIR_DB_MONTHLY

[ -d $BACKUPDIR_FILES ] || mkdir -p $BACKUPDIR_FILES
[ -d $BACKUPDIR_FILES_DAILY ] || mkdir -p $BACKUPDIR_FILES_DAILY
[ -d $BACKUPDIR_FILES_MONTHLY ] || mkdir -p $BACKUPDIR_FILES_MONTHLY


echo
echo '========================================================================='
echo "Date: `date`"
echo 

# Удаление старых резервных копий
MON_DAYS=31
let "STOR_MON_BACKUPS_DAYS = $MON_DAYS * STOR_MON_BACKUPS"

echo "DELETE OLD BACKUPS"
echo -------------------------------------------------------------------------
find ${BACKUPDIR_DB_DAILY} -type f -mtime +${STOR_DAY_BACKUPS} 
find ${BACKUPDIR_FILES_DAILY} -type f -mtime +${STOR_DAY_BACKUPS} 
find ${BACKUPDIR_DB_MONTHLY} -type f -mtime +${STOR_MON_BACKUPS_DAYS} 
find ${BACKUPDIR_FILES_MONTHLY} -type f -mtime +${STOR_MON_BACKUPS_DAYS} 

find ${BACKUPDIR_DB_DAILY} -type f -mtime +${STOR_DAY_BACKUPS} -exec rm -rf {} \;
find ${BACKUPDIR_FILES_DAILY} -type f -mtime +${STOR_DAY_BACKUPS} -exec rm -rf {} \;
find ${BACKUPDIR_DB_MONTHLY} -type f -mtime +${STOR_MON_BACKUPS_DAYS} -exec rm -rf {} \;
find ${BACKUPDIR_FILES_MONTHLY} -type f -mtime +${STOR_MON_BACKUPS_DAYS} -exec rm -rf {} \;
echo -------------------------------------------------------------------------
echo

# Определение
if [ -n "$MYSQL_CONNECT_FILES" ]; then
    MYSQL_LOGIN="--defaults-extra-file=$MYSQL_CONNECT_FILES"
else
    MYSQL_LOGIN="--user=${MYSQL_USER} --port=${MYSQL_PORT} --host=${MYSQL_HOST} --password=${MYSQL_PASSW                ORD}"
fi

# Добавление списка игнорируемых таблиц
if [ -n "$IGNORE_TABLES" ]; then
    for table in $IGNORE_TABLES ; do
        MYSQLDUMP_OPT="${MYSQLDUMP_OPT} --ignore-table=${table}"
    done
fi

# # Добавление списка таблци для которых копируется только структура
OPT_DATA=""
if [ -n "$IGNORE_DATA_TABLE" ]; then
    for table_wildcard in $IGNORE_DATA_TABLE ; do
        tables_found="`mysql ${MYSQL_LOGIN} --batch --skip-column-names -e "select CONCAT(table_schema, '.',  table_name) from information_schema.tables where table_name like '${table_wildcard}';"`"
        for table in $tables_found ; do
          OPT_DATA="${OPT_DATA} --ignore-table=${table}"
        done
    done
fi

# Создание списка баз данных для бекапа
if [ -n "$IGNORE_DB" ]; then
    db_list=""
    for db in ${IGNORE_DB} ; do
        db_list="$db_list|$db"
    done
    IGNORE_DB=`echo $db_list | sed 's/^.//'`
    IGNORE_DB="($IGNORE_DB)"
    DBLIST=`mysql ${MYSQL_LOGIN}  -sse "SHOW DATABASES;" | sed 's/ /%/g' | tr -d "| " | grep -v -P ${IGNORE_DB}`
else
    DBLIST=`mysql ${MYSQL_LOGIN}  -sse "SHOW DATABASES;" | sed 's/ /%/g' | tr -d "| "`
fi

# Определение папки для текущей резервной копии 
NUM_DAY=`date +%d`
echo 'RUN BACKUP'
if [ "$BACKUP_MONTHLY_DAY" == "$NUM_DAY" ] ; then
    CUR_DIR_BACKUP_DB=$BACKUPDIR_DB_MONTHLY
    CUR_DIR_BACKUP_FILES=$BACKUPDIR_FILES_MONTHLY
else
    CUR_DIR_BACKUP_DB=$BACKUPDIR_DB_DAILY
    CUR_DIR_BACKUP_FILES=$BACKUPDIR_FILES_DAILY
fi

# Запуск резервного копировния
DATE=`date +%Y%m%d`
for db_backup in $DBLIST ; do
    echo 
    echo -------------------------------------------------------------------------
    echo "Backup db: ${db_backup}"
    dbdump "${db_backup}" "${CUR_DIR_BACKUP_DB}/${DATE}_${db_backup}.sql"
    echo
    echo "Compression backup: $db_backup.sql"
    compression "${CUR_DIR_BACKUP_DB}/${DATE}_${db_backup}.sql"
    echo -------------------------------------------------------------------------
done
echo
echo "Backup directory: $SITE_FILES"
compression "$SITE_FILES" "$CUR_DIR_BACKUP_FILES"
echo -------------------------------------------------------------------------
BACKUP_SIZE_TOTAL=`find ${BACKUPDIR} -type f -mmin -600 -exec du -ch {} + | grep total$ | awk '{print $1}'`
echo "Total backup size: $BACKUP_SIZE_TOTAL"
echo
echo 'END BACKUP'
echo '========================================================================='
