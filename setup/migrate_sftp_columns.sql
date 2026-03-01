-- Migration: Add SFTP storage columns to users table
-- Run this if upgrading from a version before SFTP support was added.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS storage_type ENUM('local', 'sftp') DEFAULT 'local' AFTER music_directory,
    ADD COLUMN IF NOT EXISTS sftp_host VARCHAR(255) NULL AFTER storage_type,
    ADD COLUMN IF NOT EXISTS sftp_port SMALLINT UNSIGNED DEFAULT 22 AFTER sftp_host,
    ADD COLUMN IF NOT EXISTS sftp_user VARCHAR(100) NULL AFTER sftp_port,
    ADD COLUMN IF NOT EXISTS sftp_password VARCHAR(512) NULL AFTER sftp_user,
    ADD COLUMN IF NOT EXISTS sftp_path VARCHAR(255) NULL AFTER sftp_password;
