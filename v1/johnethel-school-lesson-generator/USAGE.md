---
How to Use Both Agents
1. Content Generation (MasterContentAgent)
HTTP:
# Generate content for all topics in a table
curl "http://lesson-generator.localhost:9006/content/generate?table=first_term_scheme"
# Result: "All 3 rows dispatched" (children run in parallel ~2min)
CLI:
golem agent new 'MasterContentAgent()' \
  --env SURREAL_DB_URL="http://localhost:8000" \
  --env BAML_BASE_URL="http://localhost:8001"
golem agent invoke 'MasterContentAgent()' generate_all '["first_term_scheme"]'
2. PDF Workbook (PdfAgent)
HTTP:
curl "http://lesson-generator.localhost:9006/generate-pdf-api/Basic%20Science/PRIMARY_5/teacher" -o lesson.pdf
curl "http://lesson-generator.localhost:9006/generate-pdf-api/Mathematics/PRIMARY_3/teacher" -o lesson.pdf
# Mode: "teacher" or "pupil"
CLI:
golem agent new 'PdfAgent("Basic Science", "PRIMARY_5", "teacher")'
golem agent invoke 'PdfAgent("Basic Science", "PRIMARY_5", "teacher")' pdf_generator
3. Typical Workflow
# 1. Generate lessons (parallel, ~2min)
curl "http://lesson-generator.localhost:9006/content/generate?table=first_term_scheme"
# 2. Wait for completion (~120s for 3 topics)
# 3. Generate workbook PDF (instant)
curl "http://lesson-generator.localhost:9006/generate-pdf-api/Basic%20Science/PRIMARY_5/teacher" -o workbook.pdf
# 4. Check lesson data
curl -s http://localhost:8000/sql \
  -H "Authorization: Basic cm9vdDpyb290" \
  -H "Accept: application/json" \
  --data-binary 'USE NS main DB `johnethel-school-generated-lessons`; \
    SELECT * FROM lesson_content WHERE topic_title IS NOT NULL;'
