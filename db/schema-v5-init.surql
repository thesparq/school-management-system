DELETE id_sequences;
UPSERT id_sequences:student CONTENT { type: "student", prefix: "JES", current_value: 0 };
UPSERT id_sequences:staff CONTENT { type: "staff", prefix: "EMP", current_value: 0 };
UPSERT id_sequences:admin CONTENT { type: "admin", prefix: "ADM", current_value: 0 };
