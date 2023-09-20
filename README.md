# 目的
透過terraform建立一個簡單的SPA網站，並且使用cloudfront做為CDN，以及route53做為DNS

# 前置條件
1. 安裝 AWS CLI 並有對應資源的權限
2. Terraform installed
3. Route53 持有該域名


# 大致順序 
1. 建立s3 bucket
2. 建立s3 bucket policy
3. 上傳檔案到s3 bucket  
4. 建立ACM certificate
5. 待釐清x2
6. 建立cloudfront
7. 建立route53的cloudfront紀錄

# 使用步驟
0. 輸入以下訊息到 `dev.tfvars` 檔案中(參照 dev.tfvars.example)
1. terraform init
2. terraform fmt
2. terraform plan -var-file="dev.tfvars" -out=planA
3. terraform apply planA

# 收拾
1. terraform destroy -var-file="dev.tfvars"