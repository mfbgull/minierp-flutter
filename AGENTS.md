# AGENTS.md (RULE ENGINE SPEC)

version: 1.1
mode: strict

---

# 1. GLOBAL RULE ENGINE

rule_engine:
  evaluation_order:
    - ARCHITECTURE_GUARD
    - USER_AUTHORITY_MODEL
    - CODE_GENERATION_CONSTRAINTS
    - CONTEXT_POLICY
    - TYPE_SAFETY
    - ERROR_HANDLING
    - DATABASE_RULES
    - UI_RULES
    - PERFORMANCE_RULES
    - SELF_AUDIT
    - FAILURE_CONDITIONS

---

# 2. ARCHITECTURE GUARD (NON-NEGOTIABLE)

rule ARCHITECTURE_GUARD:
  type: invariant

  frontend_stack:
    - Flutter
    - TanStack Query
    - Pluto-Grid (desktop)
    - Compact Card System (mobile)

  backend_stack:
    - Node.js
    - Express
    - TypeScript
    - SQLite (better-sqlite3)
    - Layered architecture

  violations:
    - reject: architecture modification without explicit approval

---

# 3. USER AUTHORITY MODEL

rule USER_AUTHORITY:
  type: delegation_map

  user_controls:
    - product_decisions
    - ui_ux_decisions
    - workflows
    - business_rules

  ai_controls:
    - architecture
    - api_design
    - database_schema
    - validation
    - security
    - error_handling

  forbidden_user_decision_requests:
    - mvc_vs_mvvm
    - repository_pattern_choice
    - service_layer_design
    - authentication_strategy
    - controller_structure

  ai_behavior:
    strategy: choose_simplest_solution
    explanation: minimal_if_needed_only

---

# 4. COMMUNICATION POLICY

rule COMMUNICATION:
  type: output_constraints

  style:
    - concise
    - implementation_focused
    - bullet_preferred

  forbidden:
    - long_tutorials
    - conceptual_lectures
    - repeated_explanations
    - unnecessary_theory

  terminology_policy:
    if_new_term:
      format:
        - definition_short
        - purpose_short
        - continue_to_implementation

---

# 5. CODE GENERATION CONSTRAINTS

rule CODE_OUTPUT:
  type: transformation_policy

  default_behavior:
    - no_full_file_output
    - no_unchanged_code_repetition
    - minimal_diff_only

  allowed_full_output_when:
    - file_is_new
    - user_requests_full_file
    - change_scope > 60_percent

  required_output_format:
    - changed_files_only
    - or changed_functions_only

---

# 6. CONTEXT MANAGEMENT

rule CONTEXT_POLICY:
  type: optimization

  forbidden:
    - redundant_file_reads
    - unrelated_module_loading
    - repeated_analysis
    - large_context_dumping

  preferred:
    - targeted_file_access
    - incremental_updates
    - minimal_state_reuse

---

# 7. PLANNING ENGINE

rule PLANNING:
  type: execution_pipeline

  trigger:
    condition: task_complexity > simple_fix

  steps:
    1: requirement_analysis
    2: infer_missing_requirements
    3: plan(max_steps=10)
    4: identify_affected_files
    5: implement
    6: self_audit

  constraints:
    max_plan_steps: 10

---

# 8. TYPE SAFETY RULES

rule TYPE_SAFETY:
  type: compilation_invariant

  forbidden:
    - any
    - as_any
    - ts_ignore
    - type_suppression

  required:
    - explicit_interfaces
    - typed_api_responses
    - /types_directory_for_shared_models

---

# 9. ERROR HANDLING RULES

rule ERROR_HANDLING:
  backend:
    required:
      - try_catch_controllers
      - structured_json_responses
      - no_stack_leakage

  frontend:
    required:
      - try_catch_async
      - toast_feedback
      - loading_states
      - no_silent_failures

---

# 10. DATABASE RULES

rule DATABASE:
  type: integrity_constraints

  required:
    - prepared_statements_only
    - transactional_writes
    - migration_required_for_schema_changes

  forbidden:
    - string_concatenated_sql
    - silent_schema_modification

---

# 11. SECURITY RULES

rule SECURITY:
  type: enforcement

  required:
    - input_validation
    - auth_protection
    - client_untrusted_assumption
    - no_secret_logging

---

# 12. UI RULES

rule UI_SYSTEM:
  frontend_patterns:
    desktop:
      - Pluto_Grid_for_lists

    mobile:
      breakpoint: 768px
      layout: Compact_Card_System
      required_features:
        - search
        - action_menu
        - detail_modal
        - mobile_action_bar

  constraint:
    - no_duplicate_ui_systems

---

# 13. PERFORMANCE RULES

rule PERFORMANCE:
  frontend:
    - avoid_unnecessary_rerenders
    - memoize_heavy_components
    - avoid_inline_functions_in_lists

  backend:
    - prevent_n_plus_one_queries
    - use_indexes
    - optimize_transactions

---

# 14. CHANGE IMPACT ANALYSIS

rule IMPACT_ANALYSIS:
  required_before_major_changes:
    - list_affected_modules
    - check_cross_layer_effects
    - validate_database_impact
    - detect_circular_dependencies
    - preserve_api_contracts

---

# 15. SELF-AUDIT ENGINE

rule SELF_AUDIT:
  trigger: before_task_completion

  checks:
    - typescript_errors == 0
    - lint_errors == 0
    - unused_imports == 0
    - duplicated_logic == false
    - mobile_layout_valid == true
    - desktop_layout_valid == true
    - api_contract_consistent == true
    - error_handling_complete == true
    - migrations_present_if_db_changed == true
    - security_compliance == true
    - performance_regression == false

  required_commands:
    - npm run typecheck
    - npm run lint

  failure_action:
    - continue_fixing

---

# 16. FAILURE CONDITIONS

rule FAILURE_CONDITIONS:
  type: hard_stop_blockers

  task_invalid_if_any:
    - typescript_errors_present
    - api_contract_mismatch
    - mobile_ui_broken
    - missing_migration
    - security_violation
    - architecture_violation

  enforcement:
    action: do_not_finalize
    required: fix_and_retry

---

# 17. DEFINITION OF DONE

rule DONE:
  required_states:
    - fully_typed
    - fully_error_handled
    - architecture_consistent
    - mobile_verified
    - desktop_verified
    - self_audit_passed
    - no_suppressed_errors

---

# 18. GRAPH SYSTEM

rule GRAPHIFY:
  type: knowledge_dependency

  sources:
    - graphify-out/graph.html
    - graphify-out/graph.json
    - graphify-out/GRAPH_REPORT.md

  behavior:
    before_architecture_question:
      - read_graph_report

    after_code_change:
      - run: graphify update .

---

END_RULESET
