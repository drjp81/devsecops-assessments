docker exec devsecops-assessments-v2-db-1  mariadb -e \
"CREATE DATABASE IF NOT EXISTS assessments CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'apppass';
ALTER USER 'appuser'@'%' IDENTIFIED BY 'apppass';
GRANT ALL PRIVILEGES ON assessments.* TO 'appuser'@'%';
FLUSH PRIVILEGES;"