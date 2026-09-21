-- Creates one database per microservice.
-- Runs automatically on first start of an empty postgres volume.

CREATE DATABASE user_management;
CREATE DATABASE battle;
CREATE DATABASE tamagotchi;
CREATE DATABASE notification;
CREATE DATABASE map;
CREATE DATABASE monster_raid;
CREATE DATABASE guild;
CREATE DATABASE package_registry;

-- Map Service stores geometry and queries by proximity.
\connect map
CREATE EXTENSION IF NOT EXISTS postgis;
