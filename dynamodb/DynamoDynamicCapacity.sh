#!/bin/sh

UsageExit()
{

cat <<-EOF

バッチ名：`basename $0`
機能概要：DynamoDBテーブルのプロビジョンドスループットの設定値を変更する。
実行方法：カレントディレクトリに本スクリプトがある状態で実行する。
注意事項：DynamoDBテーブルのプロビジョンドスループットの変更について
　　　　  - 縮小は１日に４回までという制限がある。
         - 拡大は、回数に制限はないが設定できるのは現在の設定値の２倍までである。
　　　　    ２倍以上に設定する場合は複数回にわけて実行する。

 Usage: $0 [--dry-run] --show <table-name>
      : $0 [--dry-run] --set <table-name> --read <read> --write <write>
      : $0 [--dry-run] --auto <table-name>
      : $0 [--dry-run] --reset <table-name>

 --dry-run
　このオプションをつけると実際にスクリプトは実行しないが、
  本オプションを外した場合に実行するコマンドラインの表示を行う。

 --show
  現在のキャパシティユニットを表示する。

 --auto
  最新の消費ユニットから計算して、必要なキャパシティユニットを増加させる。
  common.confに設定された上限値と下限値の間で設定する。
  本オプションでは、キャパシティユニットの減少は行わない。

 --reset
  最新の消費ユニットから計算して、必要最小限のキャパシティユニットに減少させる。

Ex. 

hogeのテーブルステータスを表示する。
　$ $0 --show hoge

hogeテーブルのReadを64, Writeを32に設定する。
  $ $0 --set hoge --read 64 --write 32

hogeテーブルのキャパシティを必要の量まで増加させる。
  $ $0 --auto hoge

hogeテーブルのキャパシティを必要最小限まで減少させる。
　$ $0 --reset hoge

EOF
	exit 1
}

################################################################################
# ENVIRONMENT
################################################################################

# 共通設定ファイルの読み込み
UTIL_DIR=`dirname $0`
COMMON_FILE=${UTIL_DIR}/common.conf
if [ ! -r "$COMMON_FILE" ]; then
	echo "### ERROR: ${COMMON_FILE}が読み込めません。"
	exit 1
fi
. $COMMON_FILE

READ_RATIO_AUTO=0.65
WRITE_RATIO_AUTO=0.55
READ_RATIO_RESET=0.6
WRITE_RATIO_RESET=0.5

################################################################################
# 引数チェック
################################################################################

ARGS=$@

READ_UNITS=""
WRITE_UNITS=""
TABLE_INFO=""

until [ $# -eq 0 ]
do
	case $1 in
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--show|--set|--auto|--reset)
		ARG1=$1
		shift
		;;
	--read|-r)
		IsNumeric $2 || UsageExit
		READ_UNITS=$2
		shift 2
		;;
	--write|-w)
		IsNumeric $2 || UsageExit
		WRITE_UNITS=$2
		shift 2
		;;
	$DYNAMO_TABLE1|$DYNAMO_TABLE2)
		TABLE_NAME=$1
		shift
		# テーブルごとの上限値、下限値を設定
		case $TABLE_NAME in
		$DYNAMO_TABLE1)
			READ_MAX_LIMIT=$READ_MAX_TABLE1
			READ_MIN_LIMIT=$READ_MIN_TABLE1
			WRITE_MAX_LIMIT=$WRITE_MAX_TABLE1
			WRITE_MIN_LIMIT=$WRITE_MIN_TABLE1
			;;
		$DYNAMO_TABLE2)
			READ_MAX_LIMIT=$READ_MAX_TABLE2
			READ_MIN_LIMIT=$READ_MIN_TABLE2
			WRITE_MAX_LIMIT=$WRITE_MAX_TABLE2
			WRITE_MIN_LIMIT=$WRITE_MIN_TABLE2
			;;
		esac
		;;
	*)
		UsageExit
		;;
	esac
done

if [ -z "$ARG1" ]; then
	UsageExit
elif [ -z "$TABLE_NAME" ]; then
	UsageExit
elif [ "$ARG1" = --set ]; then
	if [ -z "$READ_UNITS" -a -z "$WRITE_UNITS" ]; then
		UsageExit
	fi
fi

if [ -n "$DEBUG" ]; then
	cat <<-EOF
	DRY_RUN:$DRY_RUN
	ARG1:$ARG1
	READ_UNITS:$READ_UNITS
	WRITE_UNITS:$WRITE_UNITS
	TABLE_NAME:$TABLE_NAME
	EOF
fi

################################################################################
# FUNCTION
################################################################################
Main()
{
	LogMessage "BEGIN: `basename $0` $ARGS "

	case $ARG1 in
	--show)
		ShowTableInfo
		ShowConsumedCapacity read
		ShowConsumedCapacity write
		;;
	--set)
		SetMain
		;;
	--auto)
		AutoMain
		;;
	--reset)
		ResetMain
		;;
	esac

	LogMessage "END: `basename $0` $ARGS "
}

SetMain()
{
	InitTableInfo
	CheckTableStatus
	if [ $? -ne 0 ]; then
		ResultLogMessage "WARNING: Status is ${TABLE_STATUS}. ARGS[$ARGS] "
		exit 1
	fi

	# aws-cliによるキャパシティの変更では、read/writeの両方を指定する必要があるので、
	# 指定がない方は現在の値を取得する。
	if [ -z "$READ_UNITS" ]; then
		READ_UNITS=`GetCurrentCapacity read`
	fi
	if [ -z "$WRITE_UNITS" ]; then
		WRITE_UNITS=`GetCurrentCapacity write`
	fi

	SetCapacity "$READ_UNITS" "$WRITE_UNITS"
}

AutoMain()
{
	InitTableInfo
	CheckTableStatus
	if [ $? -ne 0 ]; then
		ResultLogMessage "WARNING: Status is ${TABLE_STATUS}. ARGS[$ARGS] "
		exit 1
	fi

	ProReadUnits=`GetCurrentCapacity read`
	ProWriteUnits=`GetCurrentCapacity write`
	NeedReadUnits=`GetNeededCapacity read`
	NeedWriteUnits=`GetNeededCapacity write`

	# 必要なキャパシティが現在の設定値よりも大きい場合は変更し、
	# 小さい場合は変更しない。
	if [ "$NeedReadUnits" -gt "$ProReadUnits" ]; then
		NewReadUnits=$NeedReadUnits
	else
		NewReadUnits=$ProReadUnits
	fi

	if [ "$NeedWriteUnits" -gt "$ProWriteUnits" ]; then
		NewWriteUnits=$NeedWriteUnits
	else
		NewWriteUnits=$ProWriteUnits
	fi

	cat <<-EOF
	Read Capacity Units: [$ProReadUnits] => [$NewReadUnits]
	need[$NeedReadUnits] max[$READ_MAX_LIMIT] min[$READ_MIN_LIMIT]
	Write Capacity Units: [$ProWriteUnits] => [$NewWriteUnits]
	need[$NeedWriteUnits] max[$WRITE_MAX_LIMIT] min[$WRITE_MIN_LIMIT]
	EOF

	# 設定値に変更がある場合のみ、apiを実行
	if [ "$ProReadUnits" -ne "$NewReadUnits" -o "$ProWriteUnits" -ne "$NewWriteUnits" ]; then
		ResultLogMessage "NOTICE: DynamoDB: Change Capacity: $TABLE_NAME"
		SetCapacity "$NewReadUnits" "$NewWriteUnits"
	else
		ResultLogMessage "INFO: ARGS[$ARGS] read[${NeedReadUnits}/${ProReadUnits}] write[${NeedWriteUnits}/${ProWriteUnits}] "
	fi
}

ResetMain()
{
	InitTableInfo
	CheckTableStatus
	if [ $? -ne 0 ]; then
		ResultLogMessage "WARNING: Status is ${TABLE_STATUS}. ARGS[$ARGS] "
		exit 1
	fi

	ProReadUnits=`GetCurrentCapacity read`
	ProWriteUnits=`GetCurrentCapacity write`
	NeedReadUnits=`GetNeededCapacity read`
	NeedWriteUnits=`GetNeededCapacity write`

	cat <<-EOF
	Read Capacity Units: [$ProReadUnits] => [$NeedReadUnits]
	max[$READ_MAX_LIMIT] min[$READ_MIN_LIMIT]
	Write Capacity Units: [$ProWriteUnits] => [$NeedWriteUnits]
	max[$WRITE_MAX_LIMIT] min[$WRITE_MIN_LIMIT]
	EOF

	# 設定値に変更がある場合のみ、apiを実行
    if [ "$ProReadUnits" -ne "$NeedReadUnits" -o "$ProWriteUnits" -ne "$NeedWriteUnits" ]; then
		ResultLogMessage "NOTICE: DynamoDB: Change Capacity: $TABLE_NAME"
		SetCapacity "$NeedReadUnits" "$NeedWriteUnits"
	else
		ResultLogMessage "INFO: ARGS[$ARGS] read[${NeedReadUnits}/${ProReadUnits}] write[${NeedWriteUnits}/${ProWriteUnits}] "
	fi
}

GetNeededCapacity()
{			
	case $1 in
	read)
		MaxUnits=$READ_MAX_LIMIT
		MinUnits=$READ_MIN_LIMIT
		case $ARG1 in
		--auto)
			NeedUnitRatio=$READ_RATIO_AUTO
			;;
		--reset)
			NeedUnitRatio=$READ_RATIO_RESET
			;;
		esac
		;;
	write)
		MaxUnits=$WRITE_MAX_LIMIT
		MinUnits=$WRITE_MIN_LIMIT
		case $ARG1 in
		--auto)
			NeedUnitRatio=$WRITE_RATIO_AUTO
			;;
		--reset)
			NeedUnitRatio=$WRITE_RATIO_RESET
			;;
		esac
		;;
	esac
	
	# 現在の設定値取得
	ProUnits=`GetCurrentCapacity $1`

	# 設定ファイルに記載した上限値、または現在の設定値の２倍のうち、小さい方が設定上限値となる。
	if [ `echo "$MaxUnits > $ProUnits * 2" | bc` -eq 1 ]; then
		MaxUnits=`echo "$ProUnits * 2" | bc`
	fi

	# 最新の消費キャパシティを取得
	ConUnits=`GetConsumedCapacity $1`

	# 設定されたレートを基準に必要なキャパシティ値を計算する。(10未満切り上げ)
	NeedUnits=`echo "scale=0; ($ConUnits / $NeedUnitRatio + 9.9) / 10 * 10" | bc `

	# 上限値と下限値を超える場合は、上限値と下限値を設定値とする。
	if [ "$NeedUnits" -gt "$MaxUnits" ]; then
		NeedUnits=$MaxUnits
	fi
	if [ "$NeedUnits" -lt "$MinUnits" ]; then
		NeedUnits=$MinUnits
	fi

	echo "$NeedUnits"
}

# SetCapacity()：
# 引数に渡された値でキャパシティを設定する。
# 第１引数：readキャパシティ
# 第２匹数：writeキャパシティ
SetCapacity()
{
	if [ $# -ne 2 ]; then
		LogMessage "ERROR: SetCapacity(): Internal Error. ARGS[$ARGS] "
		exit 1
	fi

	ReadUnits=$1
	WriteUnits=$2

	# 上限値と下限値のチェック
	if [ "$ReadUnits" -gt "$READ_MAX_LIMIT" -o "$ReadUnits" -lt "$READ_MIN_LIMIT" ]; then
		ResultLogMessage "WARNING: READ UNIT $ReadUnits is invalid. ARGS[$ARGS] "
		exit 1
	fi
	if [ "$WriteUnits" -gt "$WRITE_MAX_LIMIT" -o "$WriteUnits" -lt "$WRITE_MIN_LIMIT" ]; then
		ResultLogMessage "WARNING: WRITE UNIT $WriteUnits is invalid. ARGS[$ARGS] "
		exit 1
	fi

	# キャパシティ変更
	CheckExecCMD "aws dynamodb update-table --table-name $TABLE_NAME --provisioned-throughput ReadCapacityUnits=${ReadUnits},WriteCapacityUnits=${WriteUnits} "
}

# GetConsumedCapacity()
# 最新の消費ユニット数の取得して、標準出力に表示する。
# 直近の消費ユニットがない場合は、0を表示して復帰値1で終了する。
GetConsumedCapacity()
{
	ConsumedCapacity=`ShowConsumedCapacity $1 | jq '.Datapoints' | jq 'max_by(.Timestamp).Sum'`
	if [ "$ConsumedCapacity" = "null" ]; then
		echo 0
		return 1
	fi

	case $ARG1 in
	--auto)
		echo "scale=3; $ConsumedCapacity / 300" | bc
		;;
	--reset)
		echo "scale=3; $ConsumedCapacity / 1800" | bc
		;;
	esac

	return 0
}

ShowConsumedCapacity()
{
	case "$1" in
	read)
		METRIC_NAME=ConsumedReadCapacityUnits
		;;
	write)
		METRIC_NAME=ConsumedWriteCapacityUnits
		;;
	*)
		LogMessage "ERROR: ShowConsumedCapacity(): Internal Error. ARGS[$ARGS] "
		exit 1
		;;
	esac

	case $ARG1 in
	--show)
		StartTime=`date -d "30 minutes ago" '+%Y-%m-%dT%H:%M:%S' -u`
		EndTime=`date '+%Y-%m-%dT%H:%M:%S' -u`
		Period=300
		;;
	--auto)
		StartTime=`date -d "20 minutes ago" '+%Y-%m-%dT%H:%M:%S' -u`
		EndTime=`date '+%Y-%m-%dT%H:%M:%S' -u`
		Period=300
		;;
	--reset)
		StartTime=`date -d "40 minutes ago" '+%Y-%m-%dT%H:%M:%S' -u`
		EndTime=`date -d "10 minutes ago" '+%Y-%m-%dT%H:%M:%S' -u`
		Period=1800
		;;
	esac

	AWS_CMD="aws cloudwatch get-metric-statistics 
		--namespace AWS/DynamoDB 
		--start-time $StartTime
		--end-time $EndTime
		--period $Period
		--statistics Sum
		--metric-name $METRIC_NAME 
		--dimensions Name=TableName,Value=${TABLE_NAME}"
	
	$AWS_CMD
	if [ $? -ne 0 ]; then
		ResultLogMessage "ERROR: ShowConsumedCapacity(): aws api error. ARGS[$ARGS] "
		exit 1
	fi
}

ShowTableInfo()
{
	aws dynamodb describe-table --table-name $TABLE_NAME
	if [ $? -ne 0 ]; then
		ResultLogMessage "ERROR: GetTableInfo(): aws api error. ARGS[$ARGS] "
		exit 1
	fi
}

InitTableInfo()
{
	TABLE_INFO=`ShowTableInfo`
}

# CheckTableStatus()
# テーブルのステータスを確認する。UPDATINGなどではなく、ACTIVEであることを確認する。
# 本関数の呼び出しの前にInitTableInfo()を呼び出す必要がある。
CheckTableStatus()
{
	TABLE_STATUS=`echo $TABLE_INFO | jq ".Table.TableStatus" `
	echo $TABLE_STATUS | grep "ACTIVE" > /dev/null
	return $?
}

# GetCurrentCapacity()
# 現在のキャパシティユニットを表示する。
# 本関数の呼び出しの前にInitTableInfo()を呼び出す必要がある。
GetCurrentCapacity()
{
	case $1 in
	read)
		echo $TABLE_INFO | jq ".Table.ProvisionedThroughput.ReadCapacityUnits"
		;;
	write)
		echo $TABLE_INFO | jq ".Table.ProvisionedThroughput.WriteCapacityUnits"
		;;
	esac
}

# ログディレクトリがなければ作成
test -d $LOG_DIR || sudo mkdir -m 777 -p $LOG_DIR

Main 2>&1 | tee -a $LOG_FILE

# teeではなくMainの復帰値を本スクリプトの復帰値にする。
exit $PIPESTATUS
