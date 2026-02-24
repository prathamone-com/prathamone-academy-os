-- =============================================================================
-- 26_admission_form_complete.sql
-- Completes the ADMISSION_APP_FORM with missing fields and proper sections.
-- LAW UI-2: Use immutable attribute_codes. LAW UI-5: Labels from form_fields.
-- LAW UI-4: Constraints enforced at metadata level (is_required_override).
-- =============================================================================

DO $$
DECLARE
  v_tenant_id  UUID := '00000000-0000-0000-0000-000000000001';
  v_form_id    UUID;
  v_sec_personal   UUID := '8e24a35d-2573-4e19-8af0-b945da437be9';
  v_sec_academic   UUID := '80ef8c1f-6f49-4d49-b4d7-5c81a0e4c660';

  -- Attribute IDs
  v_attr_class_applied   UUID;
  v_attr_entrance_score  UUID;
  v_attr_prev_school     UUID;
  v_attr_guardian_name   UUID;
  v_attr_dob             UUID;
  v_attr_name            UUID;
  v_attr_category        UUID;
BEGIN

  -- Resolve form_id
  SELECT form_id INTO v_form_id
  FROM form_master WHERE form_code = 'ADMISSION_APP_FORM' AND tenant_id = v_tenant_id;

  IF v_form_id IS NULL THEN
    RAISE EXCEPTION 'ADMISSION_APP_FORM not found for tenant';
  END IF;

  -- Resolve attribute IDs
  SELECT attribute_id INTO v_attr_class_applied   FROM attribute_master WHERE attribute_code='class_applied'   AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_entrance_score  FROM attribute_master WHERE attribute_code='entrance_score'  AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_prev_school     FROM attribute_master WHERE attribute_code='previous_school' AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_guardian_name   FROM attribute_master WHERE attribute_code='guardian_name'   AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_dob             FROM attribute_master WHERE attribute_code='date_of_birth'   AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_name            FROM attribute_master WHERE attribute_code='applicant_name'  AND tenant_id=v_tenant_id;
  SELECT attribute_id INTO v_attr_category        FROM attribute_master WHERE attribute_code='admission_category' AND tenant_id=v_tenant_id;

  -- ── SECTION 1: Personal Information ──────────────────────────────────────
  -- Clear & re-seed existing Personal section fields cleanly
  DELETE FROM form_fields WHERE section_id = v_sec_personal AND tenant_id = v_tenant_id;

  INSERT INTO form_fields (tenant_id, section_id, attribute_id, widget_type, label_override, placeholder, help_text, is_required_override, sort_order) VALUES
    (v_tenant_id, v_sec_personal, v_attr_name,        'text_input',  'Full Name of Applicant', 'e.g. Priya Sharma', 'Enter the student''s legal name as per birth certificate', TRUE,  10),
    (v_tenant_id, v_sec_personal, v_attr_dob,         'date_picker', 'Date of Birth',           NULL,               'Must be between 3 and 20 years ago', TRUE,  20),
    (v_tenant_id, v_sec_personal, v_attr_guardian_name,'text_input', 'Parent / Guardian Name',  'e.g. Ramesh Sharma','Primary guardian contact name', TRUE,  30),
    (v_tenant_id, v_sec_personal, v_attr_category,    'select',      'Admission Category',      NULL,               'Select the applicable reservation category', TRUE,  40);

  -- ── SECTION 2: Academic Information ──────────────────────────────────────
  DELETE FROM form_fields WHERE section_id = v_sec_academic AND tenant_id = v_tenant_id;

  INSERT INTO form_fields (tenant_id, section_id, attribute_id, widget_type, label_override, placeholder, help_text, is_required_override, sort_order) VALUES
    (v_tenant_id, v_sec_academic, v_attr_class_applied,  'select',       'Class Applying For',     NULL,      'Select the class you are seeking admission into', TRUE,  10),
    (v_tenant_id, v_sec_academic, v_attr_prev_school,    'text_input',   'Previous School / Board', 'e.g. Delhi Public School, CBSE', 'Name of last attended school and board affiliation', FALSE, 20),
    (v_tenant_id, v_sec_academic, v_attr_entrance_score, 'number_input', 'Entrance Test Score (%)', 'e.g. 85.5', 'Score obtained in our entrance exam, if applicable', FALSE, 30);

  RAISE NOTICE 'ADMISSION_APP_FORM fields completed: 4 personal + 3 academic = 7 total fields';
END $$;

-- Verify
SELECT fs.display_label AS section, fs.sort_order AS s_ord, ff.sort_order AS f_ord,
       am.attribute_code, ff.label_override, ff.widget_type,
       COALESCE(ff.is_required_override, am.is_required) AS required
FROM form_master fm
JOIN form_sections fs ON fs.form_id=fm.form_id AND fs.tenant_id=fm.tenant_id
JOIN form_fields ff ON ff.section_id=fs.section_id AND ff.tenant_id=fs.tenant_id
JOIN attribute_master am ON am.attribute_id=ff.attribute_id AND am.tenant_id=ff.tenant_id
WHERE fm.form_code='ADMISSION_APP_FORM'
ORDER BY fs.sort_order, ff.sort_order;
