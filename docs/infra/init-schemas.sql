-- 서비스마다 스키마 하나 (contracts/README.md 7절). 테이블은 각 서비스가 Flyway 등으로 만듭니다.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA IF NOT EXISTS account;
CREATE SCHEMA IF NOT EXISTS schedule;
CREATE SCHEMA IF NOT EXISTS closet;
CREATE SCHEMA IF NOT EXISTS helper;
