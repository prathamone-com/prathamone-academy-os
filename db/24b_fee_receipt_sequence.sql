-- =============================================================================
-- PRATHAMONE ACADEMY OS — FEE RECEIPT SEQUENCE
-- File: db/24b_fee_receipt_sequence.sql
-- =============================================================================
-- Creates the PostgreSQL sequence used by the fees.py router to generate
-- unique, tenant-scoped receipt numbers in the format: RCT-{YEAR}-{SEQ:06d}
--
-- This is a GLOBAL sequence (not tenant-specific) because receipt numbers
-- must be globally unique across the platform for audit integrity.
-- The format prefix (RCT-{YEAR}-) provides human disambiguation by year.
-- =============================================================================

CREATE SEQUENCE IF NOT EXISTS fee_receipt_sequence
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 10          -- 10 pre-allocated IDs in memory for performance
    NO CYCLE;         -- Never reset — receipt numbers are permanent

COMMENT ON SEQUENCE fee_receipt_sequence IS
'Monotonically increasing receipt counter for FEE_LEDGER_ENTRY records. '
'Never cycled to ensure globally unique receipt numbers across all tenants. '
'Format used by fees.py: RCT-{YEAR}-{SEQ:06d}';
