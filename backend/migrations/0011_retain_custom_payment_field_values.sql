ALTER TABLE sales
ADD COLUMN notification_field_values_json TEXT;

-- Preserve the values still visible at migration time under their stable field
-- IDs. Later presentation edits can hide and re-enable these values without
-- rewriting the archive. Values removed before this migration cannot be
-- reconstructed from normalized history.
UPDATE sales
SET notification_field_values_json = (
  SELECT json_group_array(json_object(
    'id', json_extract(mapping_field.value, '$.id'),
    'value', json_extract(stored_field.value, '$.value')
  ))
  FROM custom_payment_sources AS source
  JOIN json_each(source.mapping_json, '$.notificationFields') AS mapping_field
  JOIN json_each(sales.notification_fields_json) AS stored_field
    ON json_extract(stored_field.value, '$.label') = json_extract(mapping_field.value, '$.label')
  WHERE source.id = sales.provider_account_id
    AND source.user_id = sales.user_id
)
WHERE provider = 'custom'
  AND notification_fields_json IS NOT NULL;
