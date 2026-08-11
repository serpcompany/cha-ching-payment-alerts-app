-- Active notification presentation edits are intended to apply to Dashboard
-- history. Older rows contain only the label/value pairs enabled when each
-- payment arrived, so retain matching values and apply the source's current
-- labels, visibility, and order without inventing unavailable values.
UPDATE sales
SET notification_fields_json = (
  SELECT json_group_array(json_object('label', label, 'value', field_value))
  FROM (
    SELECT
      json_extract(mapping_field.value, '$.label') AS label,
      json_extract(stored_field.value, '$.value') AS field_value
    FROM custom_payment_sources AS source
    JOIN json_each(source.mapping_json, '$.notificationFields') AS mapping_field
    JOIN json_each(sales.notification_fields_json) AS stored_field
      ON json_extract(stored_field.value, '$.label') = json_extract(mapping_field.value, '$.label')
    WHERE source.id = sales.provider_account_id
      AND source.user_id = sales.user_id
      AND json_extract(mapping_field.value, '$.enabled') = 1
    ORDER BY CAST(mapping_field.key AS INTEGER)
  )
)
WHERE provider = 'custom'
  AND notification_fields_json IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM custom_payment_sources AS source
    WHERE source.id = sales.provider_account_id
      AND source.user_id = sales.user_id
      AND source.mapping_json IS NOT NULL
  );
