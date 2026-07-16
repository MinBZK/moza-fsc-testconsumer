-- Eén postgres, per component een eigen database (spiegelt OpenFSC: manager en
-- controller delen geen DB — beide hebben een public.schema_migrations).
CREATE DATABASE fsc_directory;
CREATE DATABASE fsc_uitvraag_org;
CREATE DATABASE fsc_controller_uitvraag_org;
CREATE DATABASE fsc_txlog_uitvraag_org;
