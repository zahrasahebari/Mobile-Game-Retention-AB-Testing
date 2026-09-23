-- ============================================================
-- MOBILE GAME RETENTION & A/B TESTING ANALYTICS
-- DATABASE SETUP
-- ============================================================

-- Create a dedicated schema for unmodified source data
CREATE SCHEMA IF NOT EXISTS raw;


-- ------------------------------------------------------------
-- REGISTRATION DATA
-- One source row represents a player registration
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.registrations (
    reg_ts BIGINT,
    uid BIGINT
);


-- ------------------------------------------------------------
-- AUTHENTICATION DATA
-- One source row represents a player login event
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.authentications (
    auth_ts BIGINT,
    uid BIGINT
);


-- ------------------------------------------------------------
-- A/B TEST DATA
-- One source row is expected to represent one participant
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.ab_test (
    user_id BIGINT,
    revenue BIGINT,
    testgroup TEXT
);

-- Create indexes to improve join and retention-analysis performance
CREATE INDEX IF NOT EXISTS idx_registrations_uid
	ON raw.registrations (uid);

CREATE INDEX IF NOT EXISTS idx_authentication_uid_auth_ts
	ON raw.authentications (uid, auth_ts);