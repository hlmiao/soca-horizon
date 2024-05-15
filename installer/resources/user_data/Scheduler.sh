#!/bin/bash -xe

export PATH=$PATH:/usr/local/bin

# Variable will be replaced by CDK
S3_BUCKET="%%S3_BUCKET%%"
CLUSTER_ID="%%CLUSTER_ID%%"
SOCA_VERSION="%%SOCA_VERSION%%"
SOCA_INSTALL_AMI="%%SOCA_INSTALL_AMI%%"
SOCA_BASE_OS="%%BASE_OS%%"
LDAP_USERNAME="%%LDAP_USERNAME%%"
LDAP_PASSWORD="%%LDAP_PASSWORD%%"
SOCA_AUTH_PROVIDER="%%SOCA_AUTH_PROVIDER%%"
SOCA_LDAP_BASE="%%SOCA_LDAP_BASE%%"
RESET_PASSWORD_DS_LAMBDA="%%RESET_PASSWORD_DS_LAMBDA%%"
AWS_REGION="%%AWS_REGION%%"
PIP_CHINA_MIRROR="%%PIP_CHINA_MIRROR%%"
CENTOS_CHINA_REPO="%%CENTOS_CHINA_REPO%%"


function imds_get () {
  local SLASH=''
  local IMDS_HOST="http://169.254.169.254"
  local IMDS_TTL="300"
  # prepend a slash if needed
  if [[ "${1:0:1}" == '/' ]]; then
    SLASH=''
  else
    SLASH='/'
  fi
  local URL="${IMDS_HOST}${SLASH}${1}"

  # Get an Auth token
  local TOKEN=$(curl --silent -X PUT "${IMDS_HOST}/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: ${IMDS_TTL}")

  # Get the requested value and echo it back
  local OUTPUT=$(curl --silent -H "X-aws-ec2-metadata-token: ${TOKEN}" "${URL}")
  echo -n "${OUTPUT}"
}

function instance_type () {
  local INSTANCE_TYPE=$(imds_get /latest/meta-data/instance-type)
  echo -n "${INSTANCE_TYPE}"
}

function instance_family () {
  local INSTANCE_FAMILY=$(imds_get /latest/meta-data/instance-type | cut -d. -f1)
  echo -n "${INSTANCE_FAMILY}"
}

function instance_id () {
  local INSTANCE_ID=$(imds_get /latest/meta-data/instance-id)
  echo -n "${INSTANCE_ID}"
}

function instance_region () {
  local INSTANCE_REGION=$(imds_get /latest/meta-data/placement/region)
  echo -n "${INSTANCE_REGION}"
}


# Deactivate shell to make sure users won't access the cluster if it's not ready
echo "
************* SOCA FIRST TIME CONFIGURATION *************
Hold on, cluster is not ready yet.
Please wait ~30 minutes as SOCA is being installed.
Once cluster is ready to use, this message will be replaced automatically and you will be able to SSH.
*********************************************************" > /etc/nologin

AWS_AVAIL_ZONE=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION="`echo \"$AWS_AVAIL_ZONE\" | sed "s/[a-z]$//"`"
AWS_INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

if [[ "$SOCA_BASE_OS" == "amazonlinux2" ]] || [[ "$SOCA_BASE_OS" == "amazonlinux2023" ]] || [[ "$SOCA_BASE_OS" == "rhel7" ]] || [[ "$SOCA_BASE_OS" == "rhel8" ]] || [[ "$SOCA_BASE_OS" == "rhel9" ]]; then
    usermod --shell /usr/sbin/nologin ec2-user
fi

if [[ "%%BASE_OS%%" == "centos7" ]] || [[ "%%BASE_OS%%" == "centos8" ]]; then
  if [[ "$AWS_REGION" == "cn-north-1" ]] || [[ "$AWS_REGION" == "cn-northwest-1" ]]; then
    # Install SSM
    yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl restart amazon-ssm-agent
    usermod --shell /usr/sbin/nologin ec2-user
    curl -o /etc/yum.repos.d/CentOS-Base.repo $CENTOS_CHINA_REPO
  else
    usermod --shell /usr/sbin/nologin centos
  fi
fi

# Install awscli
if [[ "$SOCA_BASE_OS" == "centos7" ]] || [[ "$SOCA_BASE_OS" == "rhel7" ]]; then	
  if [[ "$AWS_REGION" == "cn-north-1" ]] || [[ "$AWS_REGION" == "cn-northwest-1" ]]; then
    yum install -y python3-pip
    PIP=$(which pip3)
    # $PIP install -i https://opentuna.cn/pypi/web/simple awscli
    $PIP install -i https://pypi.tuna.tsinghua.edu.cn/simple awscli
    export PATH=$PATH:/usr/local/bin
  else
    yum install -y python3-pip
    PIP=$(which pip3)
    $PIP install -i awscli
    export PATH=$PATH:/usr/local/bin
  fi
fi

# Disable automatic motd update if using ALI
if [[ "$SOCA_BASE_OS" == "amazonlinux2" ]] || [[ "$SOCA_BASE_OS" == "amazonlinux2023" ]]; then
  /usr/sbin/update-motd --disable
  rm /etc/cron.d/update-motd
  rm -f /etc/update-motd.d/*
fi

{
  echo "## [BEGIN] SOCA Configuration - Do Not Delete"
  echo export "SOCA_BASE_OS=\"$SOCA_BASE_OS\""
  echo export "SOCA_CONFIGURATION=\"$CLUSTER_ID\""
  echo export "AWS_DEFAULT_REGION=\"%%AWS_REGION%%\""
  echo export "SOCA_INSTALL_BUCKET=\"$S3_BUCKET\""
  echo export "SOCA_INSTALL_BUCKET_FOLDER=\"$CLUSTER_ID\""
  echo export "SOCA_VERSION=\"$SOCA_VERSION\""
  echo export "SOCA_INSTALL_AMI=\"$SOCA_INSTALL_AMI\""
  echo export "SOCA_AUTH_PROVIDER=\"$SOCA_AUTH_PROVIDER\""
  echo export "SOCA_LDAP_BASE=\"$SOCA_LDAP_BASE\""
  echo "## [END] SOCA Configuration"
} >> /etc/environment

source /etc/environment
AWS=$(command -v aws)

# Tag EBS disks manually as CFN  does not support it







EBS_IDS=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="$AWS_INSTANCE_ID" --region $AWS_REGION --query "Volumes[*].[VolumeId]" --out text | tr "\n" " ")
$AWS ec2 create-tags --resources $EBS_IDS --region $AWS_REGION --tags Key=Name,Value="$CLUSTER_ID Root Disk" "Key=soca:ClusterId,Value=$CLUSTER_ID"

# Tag Network Adapter for the Scheduler
ENI_IDS=$(aws ec2 describe-network-interfaces --filters Name=attachment.instance-id,Values="$AWS_INSTANCE_ID" --region $AWS_REGION --query "NetworkInterfaces[*].[NetworkInterfaceId]" --out text | tr "\n" " ")
$AWS ec2 create-tags --resources $ENI_IDS --region $AWS_REGION --tags Key=Name,Value="$CLUSTER_ID Scheduler Network Adapter" "Key=soca:ClusterId,Value=$CLUSTER_ID"

# Retrieve installer files from S3
echo "@reboot $AWS s3 cp s3://$S3_BUCKET/$CLUSTER_ID/scripts/SchedulerPostReboot.sh /root && /bin/bash /root/SchedulerPostReboot.sh $S3_BUCKET $CLUSTER_ID $LDAP_USERNAME '$LDAP_PASSWORD' >> /root/PostRebootConfig.log 2>&1" | crontab -
if [[ "$AWS_REGION" == "cn-north-1" ]] || [[ "$AWS_REGION" == "cn-northwest-1" ]]; then
  $AWS s3 cp s3://$S3_BUCKET/$CLUSTER_ID/scripts/config_china.cfg /root/config.cfg
else
  $AWS s3 cp s3://$S3_BUCKET/$CLUSTER_ID/scripts/config.cfg /root/
fi
$AWS s3 cp s3://$S3_BUCKET/$CLUSTER_ID/scripts/requirements.txt /root/
$AWS s3 cp s3://$S3_BUCKET/$CLUSTER_ID/scripts/Scheduler.sh /root/


# Specify the AD DS lambda function we will use to reset AD Password
if [[ "$SOCA_AUTH_PROVIDER" == "activedirectory" ]]; then
  if [[ "$RESET_PASSWORD_DS_LAMBDA" != "false" ]]; then
    echo "$RESET_PASSWORD_DS_LAMBDA" > /root/LambdaActiveDirectoryPasswordResetArn
  fi
fi



# Prepare Scheduler setup
/bin/bash /root/Scheduler.sh %%FS_DATA_PROVIDER%% %%FS_DATA_DNS%% %%FS_APPS_PROVIDER%% %%FS_APPS_DNS%% >> /root/Scheduler.sh.log 2>&1


