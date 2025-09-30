$DBUser = "root"
$DBPassword = ConvertTo-SecureString -String "rootpass" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DBUser, $DBPassword
$database = "assessments"
$sqlConnect = Open-MySqlConnection -ConnectionName MyDBCon -Server 192.168.1.188 -Database $database -Port 3306 -Credential $creds #-WarningAction SilentlyContinue -name
$sql = @"
CREATE DATABASE IF NOT EXISTS assessments CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'apppass';
ALTER USER 'appuser'@'%' IDENTIFIED BY 'apppass';
GRANT ALL PRIVILEGES ON assessments.* TO 'appuser'@'%';
FLUSH PRIVILEGES;
"@
Invoke-SqlQuery -query $sql -ErrorAction Stop -ConnectionName MyDBCon 
