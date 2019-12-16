#!/usr/bin/env bash
##
## SYNOPSIS
##   A script to purge *ANY* vpc in any AWS region where "isDefault" is true
## NOTES
##   Author: https://github.com/davidsuart
##   Sources:
##     - https://gist.github.com/jokeru/e4a25bbd95080cfd00edf1fa67b06996
##   License: MIT License (See repository)
##   Requires:
##     - bash, jq
## LINK
##   Repository: https://github.com/davidsuart/short-stories
##

# --------------------------------------------------------------------------------------------------
#
#  IMPORTANT:
#    - This script deletes things. ENSURE THAT YOUR ~/.aws/config IS CONFIGURED CORRECTLY!
#    - You must supply a "--profile=name" argument for everyone's safety
#    - This will delete *ANY* vpc with an "isDefault" true flag, even one of your own creation
#
# --------------------------------------------------------------------------------------------------

# Check at least something was supplied as an input argument
#
if [ -z "$1" ]
  then
    echo ""
    echo "************************* ERROR *************************"
    echo ""
    echo "  Error: no input parameters supplied."
    echo ""
    echo "  You must supply an exact: \"--profile=<string>\""
    echo ""
    echo "************************* ERROR *************************"
    echo ""
    exit 1
fi

# Check that the correct input argument (--profile) was supplied
#
for argument in "$@"
do
    key=$(echo $argument | cut -f1 -d=)
    val=$(echo $argument | cut -f2 -d=)   

    case "$key" in
            "--profile")
              profile=${val}
              ;;
            *)
              echo ""
              echo "************************* ERROR *************************"
              echo ""
              echo "  Error: you must supply an exact: \"--profile=<string>\""
              echo ""
              echo "  You provided:"
              echo "    key = ${key}"
              echo "    val = ${val}"
              echo ""
              echo "  WARNING - THIS SCRIPT IRRETRIEVABLY DELETES RESOURCES! "
              echo ""
              echo "************************* ERROR *************************"
              echo ""
              exit 1
              ;;
    esac    
done

echo "> using profile: [ $profile ]"

for region in $(aws ec2 describe-regions --profile ${profile} --region eu-west-1 | jq -r .Regions[].RegionName); do
  echo "> in region: ${region}"

  # Search for an "isDefault" VPC
  #
  vpc=$(aws ec2 describe-vpcs --profile ${profile} --region ${region} --filter Name=isDefault,Values=true \
    | jq -r .Vpcs[0].VpcId)
  if [ "${vpc}" != "null" ]; then
    echo "  - located a default vpc: ${vpc}"
  else
    echo "  - did not locate a default vpc in this region, next ..."
    continue
  fi

  # Decommission an internet gateway attached to an "isDefault" VPC
  #
  igw=$(aws ec2 describe-internet-gateways --profile ${profile} --region ${region} \
    --filter Name=attachment.vpc-id,Values=${vpc} | jq -r .InternetGateways[0].InternetGatewayId)
  if [ "${igw}" != "null" ]; then
    echo "  - detaching internet gateway: ${igw}"
    aws ec2 detach-internet-gateway --profile ${profile} --region ${region} --internet-gateway-id ${igw} --vpc-id ${vpc}
    echo "  - deleting internet gateway: ${igw}"
    aws ec2 delete-internet-gateway --profile ${profile} --region ${region} --internet-gateway-id ${igw}
  fi

  # Decommission any subnets within an "isDefault" VPC
  #
  subnets=$(aws ec2 describe-subnets --profile ${profile} --region ${region} --filters Name=vpc-id,Values=${vpc} \
    | jq -r .Subnets[].SubnetId)
  if [ "${subnets}" != "null" ]; then
    for subnet in ${subnets}; do
      echo "  - deleting subnet: ${subnet}"
      aws ec2 delete-subnet --profile ${profile} --region ${region} --subnet-id ${subnet}
    done
  fi

  # Purge the VPC O_o ... Don't look away, father will know if you do :jon_snow:
  #
  echo "  - purging vpc: ${vpc}"
  aws ec2 delete-vpc --profile ${profile} --region ${region} --vpc-id ${vpc}

done
