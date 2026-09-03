CREATE TABLE sales_ingestion_order (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  sale_id TEXT NOT NULL UNIQUE REFERENCES sales(id) ON DELETE CASCADE
);

INSERT INTO sales_ingestion_order (sale_id)
SELECT id FROM sales ORDER BY rowid;

CREATE TRIGGER sales_ingestion_order_after_insert
AFTER INSERT ON sales
BEGIN
  INSERT INTO sales_ingestion_order (sale_id) VALUES (NEW.id);
END;
