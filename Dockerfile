# Self-contained PostgreSQL image preloaded with the OTIF SLA monitoring
# schema, views, materialized views, RLS policies, and SAP transformation
# layer. Bakes in exactly what docker-compose.yml mounts at runtime
# (./sql:/sql, ./docker-init:/docker-entrypoint-initdb.d) so the image
# works standalone with no repo checkout required:
#
#   docker run -e POSTGRES_PASSWORD=changeme -p 5432:5432 \
#     ghcr.io/ashok007-cmd/realtime-otif-sla-automation:latest
#
FROM postgres:16-alpine

LABEL org.opencontainers.image.source="https://github.com/Ashok007-cmd/realtime-otif-sla-automation"
LABEL org.opencontainers.image.description="PostgreSQL preloaded with the OTIF SLA monitoring schema, views, materialized views, and Row-Level Security policies"
LABEL org.opencontainers.image.licenses="MIT"

ENV POSTGRES_DB=otif_monitoring
ENV POSTGRES_USER=otif_user

COPY sql/ /sql/
COPY docker-init/ /docker-entrypoint-initdb.d/
