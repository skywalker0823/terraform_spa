#!/bin/bash


# 1. Build the project
echo "確認設置"
cat dev.tfvars
# Ask if setting is ok
read -p "Is the setting ok? (y/n)" -n 1 -r

if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "\nSetting is ok\n"
else
    echo "\nSetting is not ok\n"
    exit 1
fi

echo "Execute terraform"

# terraform plan -var-file="dev.tfvars" -out=planA 
# terraform apply planA -auto-approve
# echo "Build completed successfully!"