-- 새 볼륨일 때 한 번만 실행됩니다. 서비스마다 스키마 하나, 표는 각 서비스가 Flyway로 만듭니다.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA IF NOT EXISTS account;
CREATE SCHEMA IF NOT EXISTS schedule;
CREATE SCHEMA IF NOT EXISTS closet;
CREATE SCHEMA IF NOT EXISTS helper;
