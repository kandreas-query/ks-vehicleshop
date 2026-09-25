-- ks-vehicleshop kurulum SQL
-- oxmysql otomatik tablo oluşturuyor ama manuel kurmak istersen bunu çalıştır

CREATE TABLE IF NOT EXISTS `ks_gallery_vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `model` VARCHAR(50) NOT NULL UNIQUE,
  `label` VARCHAR(100) NOT NULL DEFAULT '',
  `brand` VARCHAR(100) NOT NULL DEFAULT '',
  `category` VARCHAR(50) NOT NULL DEFAULT 'other',
  `price` INT NOT NULL DEFAULT 0,
  `stock` INT NOT NULL DEFAULT 1,
  `image` VARCHAR(255) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ks_gallery_blocklist` (
  `model` VARCHAR(50) PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ks_gallery_settings` (
  `name` VARCHAR(64) PRIMARY KEY,
  `value` VARCHAR(255) NOT NULL DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ks_gallery_showrooms` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `label` VARCHAR(100) NOT NULL DEFAULT '',
  `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
  `help` VARCHAR(100) NOT NULL DEFAULT 'Galeriye gir',
  `blip_sprite` INT NOT NULL DEFAULT 326,
  `blip_color` INT NOT NULL DEFAULT 3,
  `blip_scale` FLOAT NOT NULL DEFAULT 0.9,
  `is_default` TINYINT NOT NULL DEFAULT 0,
  `kind` VARCHAR(20) NOT NULL DEFAULT 'gallery'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ks_finance` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `plate` VARCHAR(10) NOT NULL,
  `model` VARCHAR(50) NOT NULL DEFAULT '',
  `label` VARCHAR(100) NOT NULL DEFAULT '',
  `price` INT NOT NULL DEFAULT 0,
  `down_paid` INT NOT NULL DEFAULT 0,
  `installment` INT NOT NULL DEFAULT 0,
  `installments_total` INT NOT NULL DEFAULT 0,
  `installments_left` INT NOT NULL DEFAULT 0,
  `interval_secs` INT NOT NULL DEFAULT 86400,
  `next_due_playtime` INT NOT NULL DEFAULT 0,
  `overdue_count` INT NOT NULL DEFAULT 0,
  `late_fee` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ks_finance_playtime` (
  `citizenid` VARCHAR(50) PRIMARY KEY,
  `seconds` INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `deleted_player_vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `license` VARCHAR(50) NOT NULL DEFAULT '',
  `vehicle` VARCHAR(50) NOT NULL DEFAULT '',
  `hash` INT NOT NULL DEFAULT 0,
  `mods` TEXT,
  `plate` VARCHAR(10) NOT NULL,
  `garage` VARCHAR(50) NOT NULL DEFAULT '',
  `owed` INT NOT NULL DEFAULT 0,
  `finance_id` INT NOT NULL DEFAULT 0,
  `deleted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
