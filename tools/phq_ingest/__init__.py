"""Police HQ development-side ingestion tools.

These tools run on a development computer. They convert, structure, index,
validate, sign and verify legal source material for offline use by the
Police HQ iPhone app. The installed app never calls these tools or any server.

Uploaded documents are treated strictly as *data*. Nothing inside a source
document is ever interpreted as an instruction to these tools or to the app.
"""

SCHEMA_VERSION = 1
PIPELINE_VERSION = "1.0.0"
