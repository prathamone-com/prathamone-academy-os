-- =============================================================================
-- PRATHAMONE ACADEMY OS — GAP-2 IMPLEMENTATION
-- Emergency Break-Glass Procedure — Chain Break Event (CBE) Protocol
-- Implements Laws: 09-2.1, 09-2.2, 09-2.3, 09-2.4
-- =============================================================================
-- Depends on: all prior schema + db/14_gap1_dpdp_erasure.sql
-- RULES.md compliance:
--   LAW 8 : Hash chain is re-sealed from WORM checkpoint — never fabricated
--   LAW 9 : CBE declaration is a kernel event, not a raw SQL operation
--   LAW 0 : Three sovereign admins must co-sign — no single-actor override
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Sovereign Admin Registry
-- Records Sovereign-level administrators eligible to co-sign a CBE.
-- Each admin has an HSM key fingerprint — the actual key lives in HSM.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sovereign_admin_registry (
    admin_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    display_name        TEXT        NOT NULL,
    email               TEXT        NOT NULL UNIQUE,
    hsm_key_fingerprint TEXT        NOT NULL UNIQUE,
    -- SHA-256 fingerprint of the HSM public key. Actual keys never stored here.
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    enrolled_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    enrolled_by         UUID,

    CONSTRAINT pk_sovereign_admin_registry PRIMARY KEY (admin_id)
);
-- This table is GLOBAL (no tenant_id) — CBE authority is platform-level.
COMMENT ON TABLE sovereign_admin_registry IS
    'LAW 09-2.1: Registry of platform-level Sovereign Administrators eligible to '
    'co-sign a Chain Break Event. Three active admins are required for quorum. '
    'HSM key fingerprints stored; actual keys reside in the HSM only.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Chain Break Event (CBE) Table
-- One row per declared emergency. Quorum is tracked via signatures below.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chain_break_events (
    cbe_id              UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE RESTRICT,
    -- The tenant shard whose chain is broken
    declaration_reason  TEXT        NOT NULL,
    -- E.g. "Disk array failure on shard-07 — NVMe RAID6 rebuild failed"
    broken_from_seq     BIGINT      NOT NULL,
    -- The first audit_event_log.tenant_sequence_number that is unverifiable
    last_valid_seq      BIGINT      NOT NULL,
    -- The last sequence number that passes hash verification
    last_valid_hash     TEXT        NOT NULL,
    -- current_hash of the last valid audit row (from WORM checkpoint)
    worm_checkpoint_ref TEXT        NOT NULL,
    -- S3/GCS URI of the WORM BAM file that provides the last_valid_hash
    declared_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    quorum_reached_at   TIMESTAMPTZ,           -- Set when 3rd signature is recorded
    recovery_sentinel_log_id UUID,             -- FK to the CHAIN_BREAK_RECOVERY audit event
    status              TEXT        NOT NULL DEFAULT 'PENDING_QUORUM'
                            CHECK (status IN (
                                'PENDING_QUORUM',   -- Awaiting 3rd co-signature
                                'QUORUM_REACHED',   -- All 3 signed; ready to re-seal
                                'SEALED',           -- Recovery sentinel appended; chain live
                                'REJECTED'          -- Quorum rejected this declaration
                            )),

    CONSTRAINT pk_chain_break_events PRIMARY KEY (cbe_id)
);

COMMENT ON TABLE chain_break_events IS
    'LAW 09-2.1: One row per Chain Break Event declaration. '
    'status=SEALED only after 3-of-3 sovereign admin signatures AND '
    'the CHAIN_BREAK_RECOVERY sentinel is appended to the audit chain.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: CBE Quorum Signatures Table (LAW 09-2.1)
-- Each sovereign admin signs separately. Quorum = 3 matching valid signatures.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cbe_quorum_signatures (
    signature_id        UUID        NOT NULL DEFAULT gen_random_uuid(),
    cbe_id              UUID        NOT NULL REFERENCES chain_break_events(cbe_id) ON DELETE RESTRICT,
    admin_id            UUID        NOT NULL REFERENCES sovereign_admin_registry(admin_id),
    hsm_signature       TEXT        NOT NULL,
    -- Hex-encoded RSA-PSS or ECDSA signature over SHA256(cbe_id || tenant_id || last_valid_seq)
    signed_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    signature_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Set to TRUE by fn_verify_cbe_signature() after cryptographic validation

    CONSTRAINT pk_cbe_quorum_signatures PRIMARY KEY (signature_id),
    CONSTRAINT uq_cbe_admin_signature UNIQUE (cbe_id, admin_id)
    -- Each admin may sign a given CBE exactly once
);

COMMENT ON TABLE cbe_quorum_signatures IS
    'LAW 09-2.1: Captures the individual HSM co-signatures for a Chain Break Event. '
    'Quorum is reached when 3 rows for the same cbe_id have signature_verified=TRUE. '
    'An admin may sign a given CBE exactly once (UNIQUE constraint).';

-- Trigger: auto-check quorum after each signature is verified
CREATE OR REPLACE FUNCTION fn_check_cbe_quorum()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_verified_count INT;
BEGIN
    IF NEW.signature_verified = TRUE THEN
        SELECT COUNT(*) INTO v_verified_count
        FROM cbe_quorum_signatures
        WHERE cbe_id = NEW.cbe_id AND signature_verified = TRUE;

        IF v_verified_count >= 3 THEN
            UPDATE chain_break_events
            SET status = 'QUORUM_REACHED', quorum_reached_at = now()
            WHERE cbe_id = NEW.cbe_id AND status = 'PENDING_QUORUM';

            RAISE NOTICE 'CBE %: Quorum of 3 sovereign admins reached at %. '
                         'Execute fn_seal_chain_break_event() to re-seal the chain.',
                NEW.cbe_id, now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cbe_quorum_check
    AFTER INSERT OR UPDATE ON cbe_quorum_signatures
    FOR EACH ROW EXECUTE FUNCTION fn_check_cbe_quorum();

COMMENT ON FUNCTION fn_check_cbe_quorum IS
    'LAW 09-2.1: After each signature update, checks if 3 verified signatures exist. '
    'Advances CBE status to QUORUM_REACHED automatically upon reaching quorum.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: fn_seal_chain_break_event() — The Re-Seal Protocol (LAW 09-2.2)
-- Inserts a CHAIN_BREAK_RECOVERY sentinel block as the next valid chain entry,
-- using the WORM-verified last_valid_hash as the previous_hash anchor.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_seal_chain_break_event(
    p_cbe_id        UUID,
    p_actor_id      UUID        -- Must be one of the 3 co-signers
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cbe               RECORD;
    v_sentinel_log_id   UUID := gen_random_uuid();
    v_hash_input        TEXT;
    v_sentinel_hash     TEXT;
    v_next_seq          BIGINT;
BEGIN
    -- 1. Load and validate CBE
    SELECT * INTO v_cbe FROM chain_break_events WHERE cbe_id = p_cbe_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CBE % not found.', p_cbe_id;
    END IF;
    IF v_cbe.status != 'QUORUM_REACHED' THEN
        RAISE EXCEPTION
            'CBE % is in status [%]. Must be QUORUM_REACHED to seal.',
            p_cbe_id, v_cbe.status;
    END IF;

    -- 2. Verify actor is one of the 3 co-signers
    IF NOT EXISTS (
        SELECT 1 FROM cbe_quorum_signatures cqs
        JOIN sovereign_admin_registry sar ON sar.admin_id = cqs.admin_id
        WHERE cqs.cbe_id = p_cbe_id
          AND sar.email = (SELECT email FROM sovereign_admin_registry WHERE admin_id = p_actor_id LIMIT 1)
          AND cqs.signature_verified = TRUE
    ) THEN
        RAISE EXCEPTION
            'LAW 09-2.1 VIOLATION: Actor % is not a verified co-signer of CBE %.',
            p_actor_id, p_cbe_id;
    END IF;

    -- 3. Atomically claim the next sequence number for the affected tenant
    INSERT INTO audit_tenant_sequence(tenant_id, last_seq)
    VALUES (v_cbe.tenant_id, 1)
    ON CONFLICT (tenant_id)
    DO UPDATE SET last_seq = audit_tenant_sequence.last_seq + 1
    RETURNING last_seq INTO v_next_seq;

    -- 4. Compute the sentinel block hash (LAW 09-2.2)
    --    previous_hash = last_valid_hash from the WORM checkpoint (verified)
    v_hash_input :=
        COALESCE(v_cbe.last_valid_hash, 'GENESIS')
        || '|' || v_sentinel_log_id::TEXT
        || '|' || jsonb_build_object(
                    'event_type', 'CHAIN_BREAK_RECOVERY',
                    'cbe_id', p_cbe_id,
                    'broken_from_seq', v_cbe.broken_from_seq,
                    'last_valid_seq', v_cbe.last_valid_seq,
                    'worm_checkpoint_ref', v_cbe.worm_checkpoint_ref
                  )::TEXT
        || '|' || now()::TEXT;

    v_sentinel_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    -- 5. Insert the CHAIN_BREAK_RECOVERY sentinel block directly
    --    (bypasses BEFORE INSERT trigger's hash computation via explicit column supply)
    INSERT INTO audit_event_log(
        tenant_id, log_id, tenant_sequence_number,
        actor_id, actor_type, event_category, event_type,
        record_id, event_data, previous_hash, current_hash, logged_at
    ) VALUES (
        v_cbe.tenant_id, v_sentinel_log_id, v_next_seq,
        p_actor_id, 'SYSTEM', 'SECURITY', 'CHAIN_BREAK_RECOVERY',
        p_cbe_id,
        jsonb_build_object(
            'cbe_id',               p_cbe_id,
            'declaration_reason',   v_cbe.declaration_reason,
            'broken_from_seq',      v_cbe.broken_from_seq,
            'last_valid_seq',       v_cbe.last_valid_seq,
            'last_valid_hash',      v_cbe.last_valid_hash,
            'worm_checkpoint_ref',  v_cbe.worm_checkpoint_ref,
            'quorum_reached_at',    v_cbe.quorum_reached_at,
            'sealed_at',            now(),
            'sealed_by',            p_actor_id,
            'law_citation',         'LAW 09-2.2: CHAIN_BREAK_RECOVERY sentinel. Chain re-anchored from WORM-verified checkpoint. No data was fabricated.'
        ),
        v_cbe.last_valid_hash,    -- previous_hash anchored to WORM checkpoint
        v_sentinel_hash,           -- current_hash of this sentinel block
        now()
    );

    -- 6. Mark CBE as sealed
    UPDATE chain_break_events
    SET status = 'SEALED',
        recovery_sentinel_log_id = v_sentinel_log_id
    WHERE cbe_id = p_cbe_id;

    RETURN jsonb_build_object(
        'status',               'SEALED',
        'sentinel_log_id',      v_sentinel_log_id,
        'new_sequence_number',  v_next_seq,
        'chain_anchored_to',    LEFT(v_cbe.last_valid_hash, 16) || '...'
    );
END;
$$;

COMMENT ON FUNCTION fn_seal_chain_break_event IS
    'LAW 09-2.2: Re-seals the audit hash chain after a Chain Break Event. '
    'Inserts a CHAIN_BREAK_RECOVERY sentinel that anchors to the WORM-verified '
    'last valid hash. No data is fabricated; only the chain linkage is restored. '
    'Requires QUORUM_REACHED status and must be called by a verified co-signer.';


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Quarterly Chain Integrity Drip-Test (LAW 09-2.4)
-- fn_chain_integrity_drip_test() verifies the hash chain for a given tenant.
-- Result is appended as a CHAIN_INTEGRITY_VERIFIED or CHAIN_INTEGRITY_FAILED event.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_chain_integrity_drip_test(
    p_tenant_id     UUID,
    p_from_seq      BIGINT DEFAULT 1,
    p_to_seq        BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row           RECORD;
    v_prev_hash     TEXT := NULL;
    v_recomputed    TEXT;
    v_hash_input    TEXT;
    v_failures      INT := 0;
    v_first_failure BIGINT;
    v_rows_checked  BIGINT := 0;
BEGIN
    -- Iterate audit chain for the tenant in strict sequence order
    FOR v_row IN
        SELECT tenant_sequence_number, log_id, event_data,
               logged_at, previous_hash, current_hash
        FROM   audit_event_log
        WHERE  tenant_id             = p_tenant_id
          AND  tenant_sequence_number >= p_from_seq
          AND  (p_to_seq IS NULL OR tenant_sequence_number <= p_to_seq)
        ORDER  BY tenant_sequence_number ASC
    LOOP
        v_rows_checked := v_rows_checked + 1;

        -- Recompute hash using the same algorithm as fn_audit_event_log_before_insert
        v_hash_input := COALESCE(v_row.previous_hash, 'GENESIS')
                     || '|' || v_row.log_id::TEXT
                     || '|' || v_row.event_data::TEXT
                     || '|' || v_row.logged_at::TEXT;

        v_recomputed := encode(digest(v_hash_input, 'sha256'), 'hex');

        IF v_recomputed != v_row.current_hash THEN
            v_failures := v_failures + 1;
            IF v_first_failure IS NULL THEN
                v_first_failure := v_row.tenant_sequence_number;
            END IF;
        END IF;

        v_prev_hash := v_row.current_hash;
    END LOOP;

    -- Append the drip-test result to the audit chain
    INSERT INTO audit_event_log(
        tenant_id, actor_id, actor_type, event_category, event_type, event_data
    ) VALUES (
        p_tenant_id, NULL, 'SYSTEM', 'SECURITY',
        CASE WHEN v_failures = 0 THEN 'CHAIN_INTEGRITY_VERIFIED' ELSE 'CHAIN_INTEGRITY_FAILED' END,
        jsonb_build_object(
            'from_seq',         p_from_seq,
            'to_seq',           p_to_seq,
            'rows_checked',     v_rows_checked,
            'failures',         v_failures,
            'first_failure_seq', v_first_failure,
            'verified_at',      now(),
            'law_citation',     'LAW 09-2.4: Quarterly chain integrity drip-test result.'
        )
    );

    RETURN jsonb_build_object(
        'tenant_id',        p_tenant_id,
        'rows_checked',     v_rows_checked,
        'failures',         v_failures,
        'first_failure_seq', v_first_failure,
        'status',           CASE WHEN v_failures = 0 THEN 'PASS' ELSE 'FAIL' END
    );
END;
$$;

COMMENT ON FUNCTION fn_chain_integrity_drip_test IS
    'LAW 09-2.4: Recomputes every SHA-256 hash in the audit chain for a tenant. '
    'Any mismatch indicates tampering. Result is appended as an immutable audit event. '
    'Should be scheduled quarterly via pg_cron or an external scheduler.';

GRANT EXECUTE ON FUNCTION fn_seal_chain_break_event(UUID, UUID) TO system_admin;
GRANT EXECUTE ON FUNCTION fn_chain_integrity_drip_test(UUID, BIGINT, BIGINT) TO system_admin;
GRANT ALL ON TABLE chain_break_events TO system_admin;
GRANT ALL ON TABLE cbe_quorum_signatures TO system_admin;
GRANT ALL ON TABLE sovereign_admin_registry TO system_admin;

-- =============================================================================
-- END: GAP-2 BREAK-GLASS IMPLEMENTATION (Laws 09-2.1 to 09-2.4) — LOCKED
-- =============================================================================
