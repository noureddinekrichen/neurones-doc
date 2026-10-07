-- Neurons -- schema "apm" et ses 89 tables (Vertica).
-- Rejouable sans risque : un objet deja present est ignore, jamais modifie.
-- Usage : vsql -h <serveur> -d <base> -U dbadmin -f apm-tables.sql

CREATE SCHEMA IF NOT EXISTS apm;

CREATE TABLE IF NOT EXISTS apm.spans
(
    trace_id varchar(32) NOT NULL,
    span_id varchar(16) NOT NULL,
    parent_span_id varchar(16),
    service_name varchar(255) NOT NULL,
    application varchar(255),
    environment varchar(100),
    tenant varchar(100),
    instrumentation_lib_name varchar(255),
    instrumentation_lib_version varchar(64),
    name varchar(500) NOT NULL,
    kind varchar(16),
    api_name varchar(500),
    start_time timestamptz NOT NULL,
    end_time timestamptz NOT NULL,
    duration_in_nanos int NOT NULL,
    duration_ms float NOT NULL,
    status_code varchar(16) NOT NULL DEFAULT 'UNSET',
    status_message varchar(1000),
    trace_group varchar(500),
    trace_group_duration_nanos int,
    trace_group_end_time timestamptz,
    http_method varchar(16),
    http_route varchar(500),
    http_status_code int,
    http_url varchar(2000),
    http_host varchar(500),
    http_scheme varchar(16),
    unique_transaction_hash varchar(64),
    unique_hop_hash varchar(64),
    unique_hop_seq int,
    resource_attributes long varchar(1048576),
    span_attributes long varchar(1048576),
    dropped_attributes_count int NOT NULL DEFAULT 0,
    dropped_events_count int NOT NULL DEFAULT 0,
    dropped_links_count int NOT NULL DEFAULT 0,
    ingested_at timestamptz NOT NULL DEFAULT now()
)
PARTITION BY (("timezone"('UTC', spans.start_time))::date);

CREATE TABLE IF NOT EXISTS apm.logs
(
    log_id varchar(36) NOT NULL DEFAULT uuid_generate(),
    "timestamp" timestamptz NOT NULL,
    observed_time timestamptz,
    trace_id varchar(32),
    span_id varchar(16),
    service_name varchar(255) NOT NULL,
    application varchar(255),
    environment varchar(100),
    tenant varchar(100),
    severity_text varchar(32),
    severity_number int,
    body long varchar(1048576),
    resource_attributes long varchar(1048576),
    log_attributes long varchar(1048576),
    ingested_at timestamptz NOT NULL DEFAULT now()
)
PARTITION BY (("timezone"('UTC', logs."timestamp"))::date);

CREATE TABLE IF NOT EXISTS apm.metrics_rollup
(
    bucket_time timestamptz NOT NULL,
    service_name varchar(255) NOT NULL,
    operation_name varchar(500) NOT NULL,
    environment varchar(100),
    tenant varchar(100),
    span_kind varchar(16),
    req_count int NOT NULL DEFAULT 0,
    err_count int NOT NULL DEFAULT 0,
    duration_sum_ms float NOT NULL DEFAULT 0,
    p50_ms float,
    p95_ms float,
    p99_ms float,
    computed_at timestamptz NOT NULL DEFAULT now(),
    transaction_name varchar(1024),
    http_method varchar(16),
    application varchar(256)
);

CREATE TABLE IF NOT EXISTS apm.service_edges
(
    bucket_time timestamptz NOT NULL,
    src_service varchar(255) NOT NULL,
    dst_service varchar(255) NOT NULL,
    environment varchar(100),
    tenant varchar(100),
    call_count int NOT NULL DEFAULT 0,
    err_count int NOT NULL DEFAULT 0,
    avg_duration_ms float,
    computed_at timestamptz NOT NULL DEFAULT now(),
    dst_type varchar(32),
    dst_system varchar(64),
    connection_type varchar(32)
);

CREATE TABLE IF NOT EXISTS apm.bt_groups
(
    group_id  IDENTITY ,
    application varchar(256) NOT NULL,
    name varchar(256) NOT NULL,
    created_at timestamp DEFAULT now()
);

CREATE TABLE IF NOT EXISTS apm.bt_config
(
    bt_key varchar(800) NOT NULL,
    application varchar(256) NOT NULL,
    operation_name varchar(1024) NOT NULL,
    display_name varchar(512),
    excluded boolean DEFAULT false,
    deleted boolean DEFAULT false,
    group_id int,
    updated_at timestamp DEFAULT now(),
    updated_by varchar(256),
    deleted_at timestamp,
    CONSTRAINT C_PRIMARY PRIMARY KEY (bt_key) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.bt_settings
(
    application varchar(255) NOT NULL,
    deleted_retention_days int NOT NULL DEFAULT 7,
    updated_at timestamp NOT NULL DEFAULT now(),
    CONSTRAINT pk_bt_settings PRIMARY KEY (application) ENABLED
);

CREATE TABLE IF NOT EXISTS apm.apm_health_rules
(
    id varchar(36) NOT NULL,
    name varchar(200) NOT NULL,
    metric varchar(50) NOT NULL,
    operator varchar(2) NOT NULL,
    threshold float NOT NULL,
    service_name varchar(200),
    application varchar(200),
    environment varchar(200),
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL,
    operation_name varchar(256),
    transaction_id varchar(128),
    notification_policy_id varchar(64),
    mute_until timestamp,
    notification_enabled boolean,
    evaluation_window_minutes int,
    runbook_url varchar(1024),
    CONSTRAINT C_PRIMARY PRIMARY KEY (id) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.apm_incidents
(
    id varchar(36) NOT NULL,
    title varchar(300) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    services varchar(2000),
    notes varchar(8000),
    opened_at timestamptz NOT NULL,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL,
    CONSTRAINT C_PRIMARY PRIMARY KEY (id) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.business_transaction_detection_rules
(
    id varchar(36) NOT NULL,
    rule_name varchar(256) NOT NULL,
    application varchar(256),
    service_name varchar(256),
    environment varchar(128),
    match_signal varchar(32) NOT NULL,
    match_type varchar(16) NOT NULL,
    rule_value varchar(1024) NOT NULL,
    rule_role varchar(16) NOT NULL,
    transaction_name varchar(1024),
    transaction_alias varchar(256),
    group_name varchar(256),
    original_transaction_name varchar(1024),
    priority int NOT NULL DEFAULT 100,
    enabled boolean NOT NULL DEFAULT true,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL,
    created_by varchar(256),
    updated_by varchar(256),
    CONSTRAINT pk_business_transaction_detection_rules PRIMARY KEY (id) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.business_transaction_registry
(
    business_transaction_uuid varchar(36) NOT NULL,
    signature_hash varchar(64) NOT NULL,
    application varchar(256),
    entry_service varchar(256) NOT NULL,
    transaction_name varchar(1024) NOT NULL,
    http_method varchar(16),
    original_transaction_name varchar(1024) NOT NULL,
    detection_source varchar(8) NOT NULL,
    matched_rule_uuid varchar(36),
    excluded boolean NOT NULL DEFAULT false,
    first_seen timestamp NOT NULL,
    last_seen timestamp NOT NULL,
    updated_at timestamp NOT NULL,
    display_name varchar(1024),
    CONSTRAINT pk_business_transaction_registry PRIMARY KEY (business_transaction_uuid) DISABLED,
    CONSTRAINT uq_business_transaction_registry_sig UNIQUE (signature_hash) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.business_transaction_config
(
    business_transaction_uuid varchar(36) NOT NULL,
    application varchar(256),
    display_name varchar(1024),
    excluded boolean NOT NULL DEFAULT false,
    deleted boolean NOT NULL DEFAULT false,
    deleted_at timestamp,
    group_id int,
    updated_at timestamp NOT NULL,
    updated_by varchar(256),
    CONSTRAINT pk_business_transaction_config PRIMARY KEY (business_transaction_uuid) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.transaction_notification_config
(
    transaction_id varchar(128) NOT NULL,
    application varchar(256),
    enabled boolean NOT NULL,
    notification_type varchar(32) NOT NULL,
    trigger_events long varchar(1048576) NOT NULL,
    config_json long varchar(1048576) NOT NULL,
    last_test_status varchar(32) NOT NULL,
    last_delivery_status varchar(32) NOT NULL,
    last_delivery_at timestamp,
    retry_count int NOT NULL,
    last_error long varchar(1048576),
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.transaction_notification_delivery_log
(
    transaction_id varchar(128) NOT NULL,
    trigger_event varchar(32) NOT NULL,
    bucket_time timestamp NOT NULL,
    delivery_status varchar(32) NOT NULL,
    detail long varchar(1048576),
    delivered_at timestamp NOT NULL,
    created_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.events
(
    event_id varchar(64) NOT NULL,
    event_type varchar(64) NOT NULL,
    category varchar(64) NOT NULL,
    source varchar(64) NOT NULL,
    severity varchar(32) NOT NULL DEFAULT 'info',
    status varchar(32) NOT NULL DEFAULT 'open',
    title varchar(255) NOT NULL,
    message long varchar(1048576),
    application varchar(128),
    environment varchar(64),
    service_name varchar(128),
    operation_name varchar(255),
    transaction_id varchar(255),
    trace_id varchar(64),
    span_id varchar(64),
    host_name varchar(128),
    region varchar(64),
    team_name varchar(128),
    health_rule_id varchar(64),
    incident_id varchar(64),
    fingerprint varchar(128),
    payload_json long varchar(1048576),
    tags_json long varchar(1048576),
    started_at timestamp NOT NULL DEFAULT now(),
    resolved_at timestamp,
    last_seen_at timestamp NOT NULL DEFAULT now(),
    created_at timestamp NOT NULL DEFAULT now(),
    updated_at timestamp NOT NULL DEFAULT now(),
    dedupe_count int NOT NULL DEFAULT 1,
    acknowledged_at timestamp,
    acknowledged_by varchar(255),
    resolved_by varchar(255),
    CONSTRAINT pk_apm_events PRIMARY KEY (event_id) DISABLED,
    CONSTRAINT chk_apm_events_severity CHECK ((events.severity = ANY (ARRAY['info', 'warning', 'error', 'critical']))) ENABLED,
    CONSTRAINT chk_apm_events_status CHECK ((events.status = ANY (ARRAY['open', 'acknowledged', 'resolved', 'suppressed']))) ENABLED
);

CREATE TABLE IF NOT EXISTS apm.troubleshoot_service_rollup_5m
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    operation_name varchar(512),
    application varchar(256),
    environment varchar(128),
    trace_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    avg_duration_ms float NOT NULL,
    p95_ms float NOT NULL,
    normal_count int NOT NULL,
    slow_count int NOT NULL,
    very_slow_count int NOT NULL,
    stall_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.troubleshoot_error_signature_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    service_name varchar(256),
    operation_name varchar(512),
    signature_key varchar(128) NOT NULL,
    normalized_message varchar(1024) NOT NULL,
    sample_message long varchar(1048576),
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    avg_duration_ms float NOT NULL,
    last_seen timestamp,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_summary_index
(
    trace_id varchar(64) NOT NULL,
    trace_start timestamp NOT NULL,
    duration_ms float NOT NULL,
    span_count int NOT NULL,
    error_count int NOT NULL,
    root_service varchar(256),
    root_operation varchar(512),
    application varchar(256),
    environment varchar(128),
    computed_at timestamp NOT NULL,
    operation_name_raw varchar(512),
    operation_display_name varchar(512),
    operation_type varchar(32),
    telemetry_domain varchar(32),
    entrypoint_kind varchar(32),
    root_span_kind varchar(32),
    root_http_method varchar(16),
    root_http_route varchar(512),
    session_id varchar(128),
    page_view_id varchar(128),
    user_action_id varchar(128),
    business_transaction_uuid varchar(64),
    domains_in_trace varchar(2048),
    operation_types_in_trace varchar(1024),
    services_in_trace varchar(4096),
    service_count int,
    contains_frontend boolean,
    contains_backend boolean,
    contains_database boolean,
    contains_infrastructure boolean,
    contains_http boolean,
    contains_rum boolean,
    contains_db boolean,
    contains_messaging boolean,
    contains_internal boolean,
    contains_custom boolean,
    user_id varchar(128),
    user_name varchar(255)
);

CREATE TABLE IF NOT EXISTS apm.troubleshoot_error_signature_rollup_5m
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    service_name varchar(256),
    operation_name varchar(512),
    signature_key varchar(128) NOT NULL,
    normalized_message varchar(1024) NOT NULL,
    sample_message long varchar(1048576),
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    avg_duration_ms float NOT NULL,
    last_seen timestamp,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_dependency_edges
(
    bucket_time timestamptz NOT NULL,
    src_service varchar(255) NOT NULL,
    dst_service varchar(512),
    dst_type varchar(32) NOT NULL,
    dst_system varchar(64),
    connection_type varchar(32) NOT NULL,
    environment varchar(100),
    tenant varchar(100),
    call_count int NOT NULL,
    err_count int NOT NULL,
    avg_duration_ms float,
    computed_at timestamptz NOT NULL,
    src_kind varchar(32),
    dst_node_name varchar(512) NOT NULL,
    dst_kind varchar(32) NOT NULL,
    dst_subtype varchar(64),
    dst_host varchar(512),
    dst_port int,
    dst_db_name varchar(512),
    dst_messaging_destination varchar(512),
    dst_http_route varchar(1000),
    dst_raw_target varchar(2000),
    classification_source varchar(64),
    p50_ms float,
    p95_ms float,
    p99_ms float
);

CREATE TABLE IF NOT EXISTS apm.worker_checkpoints
(
    worker_name varchar(128) NOT NULL,
    checkpoint_name varchar(128) NOT NULL,
    last_bucket_time timestamptz,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.service_resolution_rules
(
    rule_id  IDENTITY ,
    rule_type varchar(64) NOT NULL,
    match_value varchar(1000) NOT NULL,
    target_service varchar(255),
    priority int NOT NULL DEFAULT 100,
    enabled boolean NOT NULL DEFAULT true,
    notes varchar(2000),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS apm.trace_graph_visual_rules
(
    rule_id  IDENTITY ,
    match_field varchar(64) NOT NULL,
    match_operator varchar(32) NOT NULL DEFAULT 'exact',
    match_value varchar(1000) NOT NULL,
    node_icon varchar(64),
    node_category varchar(128),
    node_color varchar(16),
    priority int NOT NULL DEFAULT 100,
    enabled boolean NOT NULL DEFAULT true,
    notes varchar(2000),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS apm.alert_notification_destinations
(
    id varchar(64) NOT NULL,
    name varchar(255) NOT NULL,
    destination_type varchar(32) NOT NULL,
    enabled boolean NOT NULL,
    target_json long varchar(1048576) NOT NULL,
    template_id varchar(64),
    last_test_status varchar(32) NOT NULL,
    last_test_at timestamp,
    last_delivery_status varchar(32) NOT NULL,
    last_delivery_error long varchar(1048576),
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.alert_notification_templates
(
    id varchar(64) NOT NULL,
    name varchar(255) NOT NULL,
    channel_type varchar(32) NOT NULL,
    subject_template long varchar(1048576),
    body_template long varchar(1048576),
    payload_template long varchar(1048576),
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.alert_notification_policies
(
    id varchar(64) NOT NULL,
    name varchar(255) NOT NULL,
    enabled boolean NOT NULL,
    destination_ids_json long varchar(1048576) NOT NULL,
    repeat_interval_minutes int NOT NULL,
    dedupe_window_minutes int NOT NULL,
    send_on_status_json long varchar(1048576) NOT NULL,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.alert_notification_delivery_log
(
    id varchar(64) NOT NULL,
    destination_id varchar(64) NOT NULL,
    delivery_status varchar(32) NOT NULL,
    detail long varchar(1048576),
    delivered_at timestamp NOT NULL,
    created_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.alert_notification_dispatch_log
(
    id varchar(64) NOT NULL,
    event_id varchar(64) NOT NULL,
    health_rule_id varchar(64),
    policy_id varchar(64),
    destination_id varchar(64) NOT NULL,
    alert_status varchar(32) NOT NULL,
    delivery_status varchar(32) NOT NULL,
    detail long varchar(1048576),
    delivered_at timestamp NOT NULL,
    created_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_session_replay_batches
(
    session_id varchar(255) NOT NULL,
    app varchar(255) NOT NULL,
    sequence_number int NOT NULL,
    compressed_events_base64 long varchar(1048576) NOT NULL,
    created_at timestamp NOT NULL DEFAULT (now())::timestamptz(6),
    content_encoding varchar(32) DEFAULT 'gzip',
    page_view_id varchar(255),
    reason varchar(64),
    trigger_reason varchar(64),
    trigger_timestamp varchar(64),
    events_count int,
    first_event_at timestamp,
    last_event_at timestamp,
    page_url long varchar(1048576),
    page_load_ms float
);

CREATE TABLE IF NOT EXISTS apm.rum_frustration_signals
(
    id varchar(36) NOT NULL,
    session_id varchar(255) NOT NULL,
    app varchar(255) NOT NULL,
    type varchar(32) NOT NULL,
    target_selector long varchar(1048576) NOT NULL,
    target_text long varchar(1048576),
    click_x float NOT NULL,
    click_y float NOT NULL,
    page_url long varchar(1048576) NOT NULL,
    event_time timestamp NOT NULL,
    created_at timestamp NOT NULL DEFAULT (now())::timestamptz(6),
    user_id varchar(128),
    user_name varchar(255)
);

CREATE TABLE IF NOT EXISTS apm.event_settings
(
    id varchar(16) NOT NULL,
    retention_days int NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.metrics_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    operation_name varchar(512),
    transaction_name varchar(512),
    http_method varchar(16),
    application varchar(256),
    environment varchar(128),
    tenant varchar(128),
    span_kind varchar(32),
    req_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.metrics_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    operation_name varchar(512),
    transaction_name varchar(512),
    http_method varchar(16),
    application varchar(256),
    environment varchar(128),
    tenant varchar(128),
    span_kind varchar(32),
    req_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.service_edges_1h
(
    bucket_time timestamp NOT NULL,
    src_service varchar(256),
    dst_service varchar(256),
    environment varchar(128),
    tenant varchar(128),
    call_count int NOT NULL,
    err_count int NOT NULL,
    avg_duration_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.service_edges_1d
(
    bucket_time timestamp NOT NULL,
    src_service varchar(256),
    dst_service varchar(256),
    environment varchar(128),
    tenant varchar(128),
    call_count int NOT NULL,
    err_count int NOT NULL,
    avg_duration_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.logs_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    severity_text varchar(32),
    log_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.logs_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    severity_text varchar(32),
    log_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.events_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    service_name varchar(256),
    status varchar(64),
    severity varchar(64),
    event_type varchar(128),
    category varchar(128),
    source varchar(128),
    count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_stats_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    root_service varchar(256),
    operation_type varchar(32),
    telemetry_domain varchar(32),
    entrypoint_kind varchar(32),
    has_error boolean,
    trace_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    hist_0_10ms int NOT NULL,
    hist_10_50ms int NOT NULL,
    hist_50_100ms int NOT NULL,
    hist_100_250ms int NOT NULL,
    hist_250_500ms int NOT NULL,
    hist_500ms_1s int NOT NULL,
    hist_1s_2s int NOT NULL,
    hist_2s_5s int NOT NULL,
    hist_5s_plus int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_stats_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    root_service varchar(256),
    operation_type varchar(32),
    telemetry_domain varchar(32),
    entrypoint_kind varchar(32),
    has_error boolean,
    trace_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    hist_0_10ms int NOT NULL,
    hist_10_50ms int NOT NULL,
    hist_50_100ms int NOT NULL,
    hist_100_250ms int NOT NULL,
    hist_250_500ms int NOT NULL,
    hist_500ms_1s int NOT NULL,
    hist_1s_2s int NOT NULL,
    hist_2s_5s int NOT NULL,
    hist_5s_plus int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_views_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page_views int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_views_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page_views int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_vitals_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    vital_name varchar(32),
    sample_count int NOT NULL,
    p75_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_vitals_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    vital_name varchar(32),
    sample_count int NOT NULL,
    p75_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_load_hist_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower_s float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_load_hist_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower_s float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_vitals_hist_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    vital_name varchar(16) NOT NULL,
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_vitals_hist_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    vital_name varchar(16) NOT NULL,
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.db_stats_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    db_system varchar(128),
    db_name varchar(256),
    call_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.db_stats_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    db_system varchar(128),
    db_name varchar(256),
    call_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.event_purge_log
(
    purged_at timestamp NOT NULL,
    purged_count int NOT NULL,
    retention_days int NOT NULL,
    trigger_source varchar(16) NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.business_topology_entities
(
    entity_uuid uuid NOT NULL,
    entity_type varchar(30) NOT NULL,
    parent_uuid uuid,
    name varchar(1000) NOT NULL,
    display_name varchar(1000),
    http_method varchar(20),
    route varchar(1000),
    source_key varchar(500),
    excluded boolean NOT NULL DEFAULT false,
    deleted boolean NOT NULL DEFAULT false,
    first_seen timestamptz NOT NULL,
    last_seen timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT C_PRIMARY PRIMARY KEY (entity_uuid) DISABLED
);

CREATE TABLE IF NOT EXISTS apm.event_management_settings
(
    id varchar(16) NOT NULL,
    enabled boolean NOT NULL,
    target_json long varchar(1048576) NOT NULL,
    payload_template long varchar(1048576),
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.business_journeys
(
    id varchar(36) NOT NULL,
    name varchar(256) NOT NULL,
    description varchar(1024),
    enabled boolean NOT NULL,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL,
    created_by varchar(256),
    updated_by varchar(256),
    elevated_error_rate_threshold float,
    critical_error_rate_threshold float
);

CREATE TABLE IF NOT EXISTS apm.business_journey_steps
(
    id varchar(36) NOT NULL,
    journey_id varchar(36) NOT NULL,
    step_order int NOT NULL,
    step_name varchar(256) NOT NULL,
    step_type varchar(16) NOT NULL,
    application varchar(256) NOT NULL,
    rum_page_route varchar(512),
    bt_operation varchar(512),
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_backend_calls_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page varchar(512),
    route varchar(512),
    method varchar(16),
    call_kind varchar(32),
    backend_service_name varchar(256),
    backend_operation varchar(512),
    status_class varchar(8),
    call_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    hist_0_10ms int NOT NULL,
    hist_10_50ms int NOT NULL,
    hist_50_100ms int NOT NULL,
    hist_100_250ms int NOT NULL,
    hist_250_500ms int NOT NULL,
    hist_500ms_1s int NOT NULL,
    hist_1s_2s int NOT NULL,
    hist_2s_5s int NOT NULL,
    hist_5s_plus int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_backend_calls_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page varchar(512),
    route varchar(512),
    method varchar(16),
    call_kind varchar(32),
    backend_service_name varchar(256),
    backend_operation varchar(512),
    status_class varchar(8),
    call_count int NOT NULL,
    error_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p50_ms float NOT NULL,
    p95_ms float NOT NULL,
    p99_ms float NOT NULL,
    hist_0_10ms int NOT NULL,
    hist_10_50ms int NOT NULL,
    hist_50_100ms int NOT NULL,
    hist_100_250ms int NOT NULL,
    hist_250_500ms int NOT NULL,
    hist_500ms_1s int NOT NULL,
    hist_1s_2s int NOT NULL,
    hist_2s_5s int NOT NULL,
    hist_5s_plus int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.retention_settings
(
    area varchar(32) NOT NULL,
    retention_days int NOT NULL,
    updated_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.neurons_data_retention_history
(
    "timestamp" int NOT NULL,
    job_name varchar(64) NOT NULL,
    job_start_time int NOT NULL,
    job_end_time int NOT NULL,
    deleted_rows int NOT NULL,
    rejected_rows int NOT NULL,
    error_message varchar(2000)
);

CREATE TABLE IF NOT EXISTS apm.retention_purge_log
(
    area varchar(32) NOT NULL,
    purged_at timestamp NOT NULL,
    purged_count int NOT NULL,
    retention_days int NOT NULL,
    trigger_source varchar(16) NOT NULL,
    purged_by_table_json long varchar(1048576)
);

CREATE TABLE IF NOT EXISTS apm.rum_page_load_hist_rollup_1m
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower_s float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_vitals_hist_rollup_1m
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    vital_name varchar(16) NOT NULL,
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(256) NOT NULL,
    bucket_lower float NOT NULL,
    sample_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_errors_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page varchar(256) NOT NULL,
    error_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_page_errors_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    page varchar(256) NOT NULL,
    error_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_entries_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    service_name varchar(256),
    entry_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_entries_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    service_name varchar(256),
    entry_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_node_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    service_name varchar(256),
    span_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_node_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    service_name varchar(256),
    span_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_edge_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    src_service varchar(256),
    dst_service varchar(256),
    call_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.bt_flow_edge_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    operation_name varchar(512) NOT NULL,
    src_service varchar(256),
    dst_service varchar(256),
    call_count int NOT NULL,
    err_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.db_stats_signature_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    db_system varchar(128),
    db_name varchar(256),
    signature varchar(2000) NOT NULL,
    call_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p95_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.db_stats_signature_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    db_system varchar(128),
    db_name varchar(256),
    signature varchar(2000) NOT NULL,
    call_count int NOT NULL,
    duration_sum_ms float NOT NULL,
    p95_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.business_journey_step_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256) NOT NULL,
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(512) NOT NULL,
    execution_count int NOT NULL,
    span_count int NOT NULL,
    error_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.business_journey_step_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256) NOT NULL,
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(512) NOT NULL,
    execution_count int NOT NULL,
    span_count int NOT NULL,
    error_count int NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.service_visual_attrs_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(255) NOT NULL,
    node_icon varchar(128),
    node_category varchar(255),
    node_color varchar(64),
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.service_visual_attrs_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256),
    environment varchar(128),
    dimension_type varchar(16) NOT NULL,
    dimension_value varchar(255) NOT NULL,
    node_icon varchar(128),
    node_category varchar(255),
    node_color varchar(64),
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_apps_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    application varchar(256),
    page_views int,
    unique_pages_approx int,
    last_seen timestamp,
    app_type_attr varchar(32),
    soft_nav_count int,
    hard_nav_count int,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_apps_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    application varchar(256),
    page_views int,
    unique_pages_approx int,
    last_seen timestamp,
    app_type_attr varchar(32),
    soft_nav_count int,
    hard_nav_count int,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_overview_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    page_views int,
    total_p50_ms float,
    backend_p50_ms float,
    frontend_p50_ms float,
    first_byte_p50_ms float,
    dns_p50_ms float,
    tcp_p50_ms float,
    tls_p50_ms float,
    request_p50_ms float,
    ttfb_p50_ms float,
    response_download_p50_ms float,
    dom_interactive_p50_ms float,
    dom_content_loaded_p50_ms float,
    dom_complete_p50_ms float,
    dom_processing_p50_ms float,
    load_event_p50_ms float,
    render_p50_ms float,
    api_call_count int,
    api_error_count int,
    api_request_p50_ms float,
    api_request_p95_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_overview_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    page_views int,
    total_p50_ms float,
    backend_p50_ms float,
    frontend_p50_ms float,
    first_byte_p50_ms float,
    dns_p50_ms float,
    tcp_p50_ms float,
    tls_p50_ms float,
    request_p50_ms float,
    ttfb_p50_ms float,
    response_download_p50_ms float,
    dom_interactive_p50_ms float,
    dom_content_loaded_p50_ms float,
    dom_complete_p50_ms float,
    dom_processing_p50_ms float,
    load_event_p50_ms float,
    render_p50_ms float,
    api_call_count int,
    api_error_count int,
    api_request_p50_ms float,
    api_request_p95_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_spa_interaction_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    soft_nav_count int,
    soft_ms_p50_ms float,
    route_render_p50_ms float,
    route_data_wait_p50_ms float,
    route_api_total_p50_ms float,
    route_backend_total_p50_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_spa_interaction_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256) NOT NULL,
    soft_nav_count int,
    soft_ms_p50_ms float,
    route_render_p50_ms float,
    route_data_wait_p50_ms float,
    route_api_total_p50_ms float,
    route_backend_total_p50_ms float,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.application_services_rollup_1h
(
    bucket_time timestamp NOT NULL,
    application varchar(256) NOT NULL,
    service_name varchar(256) NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.application_services_rollup_1d
(
    bucket_time timestamp NOT NULL,
    application varchar(256) NOT NULL,
    service_name varchar(256) NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_errors_rollup_1h
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    message varchar(2000) NOT NULL,
    error_type varchar(256),
    occurrence_count int NOT NULL,
    impacted_pages_json long varchar(1048576),
    last_seen timestamp NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_errors_rollup_1d
(
    bucket_time timestamp NOT NULL,
    service_name varchar(256),
    application varchar(256),
    environment varchar(128),
    message varchar(2000) NOT NULL,
    error_type varchar(256),
    occurrence_count int NOT NULL,
    impacted_pages_json long varchar(1048576),
    last_seen timestamp NOT NULL,
    computed_at timestamp NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_dependency_edges_rollup_1h
(
    bucket_time timestamptz NOT NULL,
    src_service varchar(255) NOT NULL,
    src_kind varchar(32),
    dst_node_name varchar(512) NOT NULL,
    dst_kind varchar(32) NOT NULL,
    dst_subtype varchar(64),
    dst_service varchar(512),
    dst_host varchar(512),
    dst_port int,
    dst_db_name varchar(512),
    dst_messaging_destination varchar(512),
    dst_http_route varchar(1000),
    dst_raw_target varchar(2000),
    dst_type varchar(32) NOT NULL,
    dst_system varchar(64),
    connection_type varchar(32) NOT NULL,
    classification_source varchar(64),
    environment varchar(100),
    tenant varchar(100),
    call_count int NOT NULL,
    err_count int NOT NULL,
    avg_duration_ms float,
    p50_ms float,
    p95_ms float,
    p99_ms float,
    computed_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.trace_dependency_edges_rollup_1d
(
    bucket_time timestamptz NOT NULL,
    src_service varchar(255) NOT NULL,
    src_kind varchar(32),
    dst_node_name varchar(512) NOT NULL,
    dst_kind varchar(32) NOT NULL,
    dst_subtype varchar(64),
    dst_service varchar(512),
    dst_host varchar(512),
    dst_port int,
    dst_db_name varchar(512),
    dst_messaging_destination varchar(512),
    dst_http_route varchar(1000),
    dst_raw_target varchar(2000),
    dst_type varchar(32) NOT NULL,
    dst_system varchar(64),
    connection_type varchar(32) NOT NULL,
    classification_source varchar(64),
    environment varchar(100),
    tenant varchar(100),
    call_count int NOT NULL,
    err_count int NOT NULL,
    avg_duration_ms float,
    p50_ms float,
    p95_ms float,
    p99_ms float,
    computed_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS apm.rum_events
(
    trace_id varchar(32) NOT NULL,
    span_id varchar(16) NOT NULL,
    parent_span_id varchar(16),
    service_name varchar(256) NOT NULL,
    application varchar(256),
    environment varchar(128),
    tenant varchar(128),
    name varchar(64) NOT NULL,
    rum_kind varchar(32),
    rum_platform varchar(16),
    session_id varchar(128),
    page_path varchar(512),
    page_url varchar(2048),
    browser_name varchar(128),
    os_name varchar(128),
    device_type varchar(64),
    geo_country varchar(8),
    geo_country_name varchar(128),
    geo_region varchar(128),
    geo_city varchar(128),
    geo_lat float,
    geo_lon float,
    vital_name varchar(16),
    vital_value_ms float,
    start_time timestamptz NOT NULL,
    end_time timestamptz,
    duration_ms float,
    status_code varchar(16),
    status_message varchar(1024),
    resource_attributes long varchar(1048576),
    span_attributes long varchar(1048576)
)
PARTITION BY (("timezone"('UTC', rum_events.start_time))::date);
