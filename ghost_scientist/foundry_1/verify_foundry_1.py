#!/usr/bin/env python3
"""Fail-closed integrated verification for all current Foundry-1 iterations."""

from __future__ import annotations

import ast
import json
import pathlib

from freeze_foundry_1 import verify
from freeze_tensor_forge_component import verify as verify_tensor_component
from freeze_external_application_intake import verify as verify_external_intake
from freeze_external_validation_v1 import verify as verify_external_validation
from freeze_aten_prospective_v2 import verify as verify_aten_v2
from freeze_aten_prospective_v2_1 import verify as verify_aten_v21
from freeze_aten_prospective_v2_2 import verify as verify_aten_v22
from freeze_semantic_prospective_v1 import verify as verify_semantic_prefreeze
from freeze_semantic_result_v1 import verify as verify_semantic_result
from freeze_external_validation_v4 import verify as verify_external_validation_v4
from freeze_polymorphic_prospective_v1 import (
    verify as verify_polymorphic_prefreeze,
)
from freeze_polymorphic_result_v1 import verify as verify_polymorphic_result
from freeze_external_control_execution_v1 import (
    verify as verify_control_execution_prefreeze,
)
from freeze_external_control_result_v1 import (
    verify as verify_control_execution_result,
)
from freeze_stitch_source_result_v1 import (
    verify as verify_stitch_source_result,
)
from freeze_stitch_metamorphic_v1 import (
    verify as verify_stitch_metamorphic_prefreeze,
)
from freeze_stitch_metamorphic_result_v1 import (
    verify as verify_stitch_metamorphic_result,
)
from freeze_enumo_source_closure_v1 import (
    verify as verify_enumo_source_closure,
)
from freeze_control_two_route_v1 import (
    verify as verify_control_two_route,
)
from freeze_babble_source_result_v1 import (
    verify as verify_babble_source_result,
)
from freeze_babble_metamorphic_v1 import (
    verify as verify_babble_metamorphic_prefreeze,
)
from freeze_babble_metamorphic_result_v1 import (
    verify as verify_babble_metamorphic_result,
)
from freeze_enumo_source_result_v1 import (
    verify as verify_enumo_source_result,
)
from freeze_enumo_metamorphic_v1 import (
    verify as verify_enumo_metamorphic_prefreeze,
)
from freeze_enumo_metamorphic_result_v1 import (
    verify as verify_enumo_metamorphic_result,
)
from freeze_enumo_power_diagnostic_v1 import (
    verify as verify_enumo_power_diagnostic,
)
from freeze_control_four_route_v1 import (
    verify as verify_control_four_route,
)
from freeze_isamore_reduced_route_v1 import (
    verify as verify_isamore_reduced_route,
)
from freeze_diversity_calibration_v1 import (
    verify as verify_diversity_calibration,
)
from freeze_external_validation_v5 import (
    verify as verify_external_validation_v5,
)
from freeze_diversity_candidate_v1 import (
    verify as verify_diversity_candidate,
)
from freeze_diversity_result_v1 import (
    verify as verify_diversity_result,
)
from freeze_diversity_failure_calibration_v1 import (
    verify as verify_diversity_failure_calibration,
)
from freeze_external_validation_v6 import (
    verify as verify_external_validation_v6,
)
from freeze_pareto_candidate_v1 import (
    verify as verify_pareto_candidate,
)
from freeze_pareto_authorization_result_v1 import (
    verify as verify_pareto_authorization_result,
)
from freeze_pareto_remediation_v1 import (
    verify as verify_pareto_remediation,
)
from freeze_pareto_remediation_v2 import (
    verify as verify_pareto_remediation_v2,
)
from freeze_pareto_remediation_v3 import (
    verify as verify_pareto_remediation_v3,
)
from freeze_pareto_remediation_v4 import (
    verify as verify_pareto_remediation_v4,
)
from freeze_pareto_remediation_v5 import (
    verify as verify_pareto_remediation_v5,
)
from freeze_pareto_remediation_v6 import (
    verify as verify_pareto_remediation_v6,
)
from freeze_pareto_remediation_v7 import (
    verify as verify_pareto_remediation_v7,
)
from freeze_pareto_remediation_v8 import (
    verify as verify_pareto_remediation_v8,
)
from freeze_pareto_remediation_v9 import (
    verify as verify_pareto_remediation_v9,
)
from freeze_pareto_remediation_v10 import (
    verify as verify_pareto_remediation_v10,
)
from freeze_pareto_remediation_v11 import (
    verify as verify_pareto_remediation_v11,
)
from freeze_pareto_remediation_v12 import (
    verify as verify_pareto_remediation_v12,
)
from freeze_pareto_remediation_v13 import (
    verify as verify_pareto_remediation_v13,
)
from freeze_isamore_acquisition_v2 import (
    verify as verify_isamore_acquisition_v2,
)
from freeze_isamore_dependency_bridge_v3 import (
    verify as verify_isamore_dependency_bridge_v3,
)
from freeze_isamore_dependency_bridge_v4 import (
    verify as verify_isamore_dependency_bridge_v4,
)
from freeze_isamore_dependency_bridge_v5 import (
    verify as verify_isamore_dependency_bridge_v5,
)
from freeze_isamore_dependency_bridge_v6 import (
    verify as verify_isamore_dependency_bridge_v6,
)
from freeze_isamore_dependency_bridge_v7 import (
    verify as verify_isamore_dependency_bridge_v7,
)
from freeze_isamore_dependency_bridge_v8 import (
    verify as verify_isamore_dependency_bridge_v8,
)
from freeze_isamore_dependency_bridge_v9 import (
    verify as verify_isamore_dependency_bridge_v9,
)
from freeze_isamore_dependency_bridge_v10 import (
    verify as verify_isamore_dependency_bridge_v10,
)
from freeze_isamore_dependency_bridge_v11 import (
    verify as verify_isamore_dependency_bridge_v11,
)
from freeze_isamore_dependency_bridge_v12 import (
    verify as verify_isamore_dependency_bridge_v12,
)
from freeze_isamore_dependency_bridge_v13 import (
    verify as verify_isamore_dependency_bridge_v13,
)
from freeze_isamore_dependency_bridge_v14 import (
    verify as verify_isamore_dependency_bridge_v14,
)
from freeze_isamore_dependency_bridge_v15 import (
    verify as verify_isamore_dependency_bridge_v15,
)
from freeze_isamore_dependency_bridge_v16 import (
    verify as verify_isamore_dependency_bridge_v16,
)
from freeze_isamore_dependency_bridge_v17 import (
    verify as verify_isamore_dependency_bridge_v17,
)
from freeze_isamore_dependency_bridge_v18 import (
    verify as verify_isamore_dependency_bridge_v18,
)
from freeze_isamore_dependency_bridge_v19 import (
    verify as verify_isamore_dependency_bridge_v19,
)
from freeze_foundry_remediation_v20 import (
    verify as verify_foundry_remediation_v20,
)
from freeze_enumo_tensor_feasibility_v1 import (
    verify as verify_enumo_tensor_feasibility_prefreeze,
)
from freeze_enumo_tensor_feasibility_result_v1 import (
    verify as verify_enumo_tensor_feasibility_result,
)
from freeze_enumo_tensor_rule_reuse_v1 import (
    verify as verify_enumo_tensor_rule_reuse_prefreeze,
)
from freeze_enumo_tensor_rule_reuse_result_v1 import (
    verify as verify_enumo_tensor_rule_reuse_result,
)
from freeze_pareto_v08_search_distinction_v1 import (
    verify as verify_pareto_v08_search_distinction_prefreeze,
)
from freeze_pareto_v08_search_distinction_result_v1 import (
    verify as verify_pareto_v08_search_distinction_result,
)
from freeze_eggmind_reproduction_sufficiency_result_v1 import (
    verify as verify_eggmind_reproduction_sufficiency_result,
)
from freeze_isamore_exact_artifact_ingress_result_v1 import (
    verify as verify_isamore_exact_artifact_ingress_result,
)
from freeze_sympy_cse_control_v1 import (
    verify as verify_sympy_cse_control_prefreeze,
)
from freeze_sympy_cse_control_execution_amendment_v1 import (
    verify as verify_sympy_cse_execution_amendment,
)
from freeze_sympy_cse_control_result_v1 import (
    verify as verify_sympy_cse_control_result,
)
from independent_diversity_tool_evaluator import (
    parse_library as parse_diversity_library,
)
from independent_pareto_tool_evaluator import (
    parse_library as parse_pareto_library,
)
from independent_evaluator import parse_tool


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(f"FOUNDRY_1_VERIFY_FAIL: {message}")


def load(name: str, version: str) -> dict:
    payload = json.loads((RESULTS / name).read_text(encoding="utf-8"))
    require(payload["version"] == version, f"{name} version mismatch")
    return payload


def main() -> None:
    verify()
    tensor_component_freeze = verify_tensor_component()
    external_intake_freeze = verify_external_intake()
    external_validation_freeze = verify_external_validation()
    aten_v2_freeze = verify_aten_v2()
    aten_v21_freeze = verify_aten_v21()
    aten_v22_freeze = verify_aten_v22()
    semantic_prefreeze = verify_semantic_prefreeze()
    semantic_result_freeze = verify_semantic_result()
    external_validation_v4_freeze = verify_external_validation_v4()
    polymorphic_prefreeze = verify_polymorphic_prefreeze()
    polymorphic_result_freeze = verify_polymorphic_result()
    control_execution_prefreeze = verify_control_execution_prefreeze()
    control_execution_result = verify_control_execution_result()
    stitch_source_result = verify_stitch_source_result()
    stitch_metamorphic_prefreeze = verify_stitch_metamorphic_prefreeze()
    stitch_metamorphic_result = verify_stitch_metamorphic_result()
    enumo_source_closure = verify_enumo_source_closure()
    control_two_route = verify_control_two_route()
    babble_source_result = verify_babble_source_result()
    babble_metamorphic_prefreeze = verify_babble_metamorphic_prefreeze()
    babble_metamorphic_result = verify_babble_metamorphic_result()
    enumo_source_result = verify_enumo_source_result()
    enumo_metamorphic_prefreeze = verify_enumo_metamorphic_prefreeze()
    enumo_metamorphic_result = verify_enumo_metamorphic_result()
    enumo_power_diagnostic = verify_enumo_power_diagnostic()
    control_four_route = verify_control_four_route()
    isamore_reduced_route = verify_isamore_reduced_route()
    diversity_calibration = verify_diversity_calibration()
    external_validation_v5 = verify_external_validation_v5()
    diversity_candidate = verify_diversity_candidate()
    diversity_result = verify_diversity_result()
    diversity_failure_calibration = verify_diversity_failure_calibration()
    external_validation_v6 = verify_external_validation_v6()
    pareto_candidate = verify_pareto_candidate()
    pareto_authorization_result = verify_pareto_authorization_result()
    pareto_remediation = verify_pareto_remediation()
    pareto_remediation_v2 = verify_pareto_remediation_v2()
    pareto_remediation_v3 = verify_pareto_remediation_v3()
    pareto_remediation_v4 = verify_pareto_remediation_v4()
    pareto_remediation_v5 = verify_pareto_remediation_v5()
    pareto_remediation_v6 = verify_pareto_remediation_v6()
    pareto_remediation_v7 = verify_pareto_remediation_v7()
    pareto_remediation_v8 = verify_pareto_remediation_v8()
    pareto_remediation_v9 = verify_pareto_remediation_v9()
    pareto_remediation_v10 = verify_pareto_remediation_v10()
    pareto_remediation_v11 = verify_pareto_remediation_v11()
    pareto_remediation_v12 = verify_pareto_remediation_v12()
    pareto_remediation_v13 = verify_pareto_remediation_v13()
    isamore_acquisition_v2 = verify_isamore_acquisition_v2()
    isamore_dependency_bridge_v3 = verify_isamore_dependency_bridge_v3()
    isamore_dependency_bridge_v4 = verify_isamore_dependency_bridge_v4()
    isamore_dependency_bridge_v5 = verify_isamore_dependency_bridge_v5()
    isamore_dependency_bridge_v6 = verify_isamore_dependency_bridge_v6()
    isamore_dependency_bridge_v7 = verify_isamore_dependency_bridge_v7()
    isamore_dependency_bridge_v8 = verify_isamore_dependency_bridge_v8()
    isamore_dependency_bridge_v9 = verify_isamore_dependency_bridge_v9()
    isamore_dependency_bridge_v10 = verify_isamore_dependency_bridge_v10()
    isamore_dependency_bridge_v11 = verify_isamore_dependency_bridge_v11()
    isamore_dependency_bridge_v12 = verify_isamore_dependency_bridge_v12()
    isamore_dependency_bridge_v13 = verify_isamore_dependency_bridge_v13()
    isamore_dependency_bridge_v14 = verify_isamore_dependency_bridge_v14()
    isamore_dependency_bridge_v15 = verify_isamore_dependency_bridge_v15()
    isamore_dependency_bridge_v16 = verify_isamore_dependency_bridge_v16()
    isamore_dependency_bridge_v17 = verify_isamore_dependency_bridge_v17()
    isamore_dependency_bridge_v18 = verify_isamore_dependency_bridge_v18()
    isamore_dependency_bridge_v19 = verify_isamore_dependency_bridge_v19()
    foundry_remediation_v20 = verify_foundry_remediation_v20()
    enumo_tensor_feasibility_prefreeze = (
        verify_enumo_tensor_feasibility_prefreeze()
    )
    enumo_tensor_feasibility_result = (
        verify_enumo_tensor_feasibility_result()
    )
    enumo_tensor_rule_reuse_prefreeze = (
        verify_enumo_tensor_rule_reuse_prefreeze()
    )
    enumo_tensor_rule_reuse_result = (
        verify_enumo_tensor_rule_reuse_result()
    )
    pareto_v08_search_distinction_prefreeze = (
        verify_pareto_v08_search_distinction_prefreeze()
    )
    pareto_v08_search_distinction_result = (
        verify_pareto_v08_search_distinction_result()
    )
    eggmind_reproduction_sufficiency_result = (
        verify_eggmind_reproduction_sufficiency_result()
    )
    isamore_exact_artifact_ingress_result = (
        verify_isamore_exact_artifact_ingress_result()
    )
    sympy_cse_control_prefreeze = verify_sympy_cse_control_prefreeze()
    sympy_cse_execution_amendment = (
        verify_sympy_cse_execution_amendment()
    )
    sympy_cse_control_result = verify_sympy_cse_control_result()
    for path in sorted(HERE.glob("*.py")):
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

    phase1 = load("phase1.json", "FOUNDRY_PHASE1_V1")
    phase2 = load("phase2.json", "FOUNDRY_PHASE2_V1")
    remediation = load("phase3_remediation.json", "FOUNDRY_REMEDIATION_V1")
    readiness = load("readiness.json", "FOUNDRY_READINESS_RECOMPUTE_V1")
    dedup = load("phase4_tensor_dedup.json", "FOUNDRY_TENSOR_DEDUP_AUDIT_V1")
    iteration11 = load(
        "readiness_iteration_1_1.json", "FOUNDRY_READINESS_ITERATION_1_1"
    )
    corpus = load(
        "phase6_external_corpus.json", "FOUNDRY_EXTERNAL_CORPUS_INTAKE_V1"
    )
    iteration12 = load(
        "readiness_iteration_1_2.json", "FOUNDRY_READINESS_ITERATION_1_2"
    )
    intake = load(
        "phase7_control_intake.json", "FOUNDRY_CONTROL_INTAKE_VERIFY_V1"
    )
    iteration13 = load(
        "readiness_iteration_1_3.json", "FOUNDRY_READINESS_ITERATION_1_3"
    )
    resource_audit = load(
        "phase8_resource_audit.json", "FOUNDRY_RESOURCE_INTEGRATION_AUDIT_V2"
    )
    iteration14 = load(
        "readiness_iteration_1_4.json", "FOUNDRY_READINESS_ITERATION_1_4"
    )
    admission = load(
        "phase9_future_tool_admission.json",
        "FOUNDRY_FUTURE_TOOL_ADMISSION_V1",
    )
    iteration15 = load(
        "readiness_iteration_1_5.json", "FOUNDRY_READINESS_ITERATION_1_5"
    )
    tensor_forge = load(
        "phase10_tensor_forge.json", "FOUNDRY_TENSOR_FORGE_RESULT_V1"
    )
    tensor_eval = load(
        "phase11_independent_tensor_eval.json",
        "FOUNDRY_INDEPENDENT_TENSOR_TOOL_EVAL_V1",
    )
    tensor_native = load(
        "phase12_tensor_native_resource.json",
        "FOUNDRY_TENSOR_NATIVE_RESOURCE_AUDIT_V1",
    )
    iteration16 = load(
        "readiness_iteration_1_6.json", "FOUNDRY_READINESS_ITERATION_1_6"
    )
    iteration17 = load(
        "readiness_iteration_1_7.json", "FOUNDRY_READINESS_ITERATION_1_7"
    )
    external_trace = load(
        "phase15_external_application_trace.json",
        "FOUNDRY_EXTERNAL_APPLICATION_TRACE_V1",
    )
    reachability = load(
        "phase16_external_tool_reachability.json",
        "FOUNDRY_EXTERNAL_TOOL_REACHABILITY_V1",
    )
    iteration18 = load(
        "readiness_iteration_1_8.json", "FOUNDRY_READINESS_ITERATION_1_8"
    )
    aten_forge = load(
        "phase17_aten_tool_forge.json", "FOUNDRY_ATEN_FORGE_RESULT_V1"
    )
    aten_eval = load(
        "phase18_independent_aten_eval.json",
        "FOUNDRY_INDEPENDENT_ATEN_EVAL_V1",
    )
    aten_audit = load(
        "phase19_aten_resource_native.json",
        "FOUNDRY_ATEN_RESOURCE_NATIVE_AUDIT_V1",
    )
    iteration19 = load(
        "readiness_iteration_1_9.json", "FOUNDRY_READINESS_ITERATION_1_9"
    )
    prospective_infra = load(
        "phase22_v2_infrastructure_failure.json",
        "FOUNDRY_ATEN_PROSPECTIVE_INFRA_FAILURE_V2",
    )
    prospective_v21_resource = load(
        "phase22_1_prospective_resource_audit.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2_1",
    )
    prospective_v22 = load(
        "phase23_prospective_aten_trial_v2_2.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESULT_V2_2",
    )
    prospective_v22_resource = load(
        "phase24_prospective_resource_v2_2.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2_2",
    )
    iteration20 = load(
        "readiness_iteration_2_0.json", "FOUNDRY_READINESS_ITERATION_2_0"
    )
    semantic_forge = load(
        "phase25_semantic_grammar_forge.json",
        "FOUNDRY_SEMANTIC_GRAMMAR_FORGE_RESULT_V1",
    )
    semantic_eval = load(
        "phase26_independent_semantic_eval.json",
        "FOUNDRY_INDEPENDENT_SEMANTIC_EVAL_V1",
    )
    semantic_native = load(
        "phase27_semantic_native_dedup.json",
        "FOUNDRY_SEMANTIC_NATIVE_DEDUP_V1",
    )
    semantic_resource = load(
        "phase28_semantic_resource_audit.json",
        "FOUNDRY_SEMANTIC_RESOURCE_AUDIT_V1",
    )
    iteration21 = load(
        "readiness_iteration_2_1.json", "FOUNDRY_READINESS_ITERATION_2_1"
    )
    polymorphic_forge = load(
        "phase29_polymorphic_semantic_forge.json",
        "FOUNDRY_POLYMORPHIC_SEMANTIC_FORGE_RESULT_V1",
    )
    polymorphic_eval = load(
        "phase30_independent_polymorphic_eval.json",
        "FOUNDRY_INDEPENDENT_POLYMORPHIC_EVAL_V1",
    )
    polymorphic_native = load(
        "phase31_polymorphic_native_dedup.json",
        "FOUNDRY_POLYMORPHIC_NATIVE_DEDUP_V1",
    )
    polymorphic_resource = load(
        "phase32_polymorphic_resource_audit.json",
        "FOUNDRY_POLYMORPHIC_RESOURCE_AUDIT_V1",
    )
    iteration22 = load(
        "readiness_iteration_2_2.json", "FOUNDRY_READINESS_ITERATION_2_2"
    )
    stitch_control = load(
        "phase33_stitch_control_conformance.json",
        "FOUNDRY_STITCH_CONTROL_CONFORMANCE_V1",
    )
    stitch_resource = load(
        "phase34_stitch_control_resource_audit.json",
        "FOUNDRY_STITCH_CONTROL_RESOURCE_AUDIT_V1",
    )
    iteration23 = load(
        "readiness_iteration_2_3.json", "FOUNDRY_READINESS_ITERATION_2_3"
    )
    stitch_source_control = load(
        "phase35_stitch_source_control.json",
        "FOUNDRY_STITCH_SOURCE_CONTROL_V1",
    )
    stitch_source_resource = load(
        "phase36_stitch_source_resource_audit.json",
        "FOUNDRY_STITCH_SOURCE_RESOURCE_AUDIT_V1",
    )
    iteration24 = load(
        "readiness_iteration_2_4.json", "FOUNDRY_READINESS_ITERATION_2_4"
    )
    stitch_metamorphic = load(
        "phase37_stitch_metamorphic_control.json",
        "FOUNDRY_STITCH_METAMORPHIC_CONTROL_V1",
    )
    stitch_metamorphic_resource = load(
        "phase38_stitch_metamorphic_resource_audit.json",
        "FOUNDRY_STITCH_METAMORPHIC_RESOURCE_AUDIT_V1",
    )
    iteration25 = load(
        "readiness_iteration_2_5.json", "FOUNDRY_READINESS_ITERATION_2_5"
    )
    enumo_closure = load(
        "phase39_enumo_source_closure.json",
        "FOUNDRY_ENUMO_SOURCE_CLOSURE_V1",
    )
    iteration26 = load(
        "readiness_iteration_2_6.json", "FOUNDRY_READINESS_ITERATION_2_6"
    )
    route_audit = load(
        "phase40_control_two_route_audit.json",
        "FOUNDRY_CONTROL_TWO_ROUTE_AUDIT_V1",
    )
    iteration27 = load(
        "readiness_iteration_2_7.json", "FOUNDRY_READINESS_ITERATION_2_7"
    )
    babble_source_control = load(
        "phase41_babble_source_control.json",
        "FOUNDRY_BABBLE_SOURCE_CONTROL_V1",
    )
    babble_source_resource = load(
        "phase42_babble_source_resource_audit.json",
        "FOUNDRY_BABBLE_SOURCE_RESOURCE_AUDIT_V1",
    )
    iteration28 = load(
        "readiness_iteration_2_8.json", "FOUNDRY_READINESS_ITERATION_2_8"
    )
    babble_metamorphic = load(
        "phase43_babble_metamorphic_control.json",
        "FOUNDRY_BABBLE_METAMORPHIC_CONTROL_V1",
    )
    babble_metamorphic_resource = load(
        "phase44_babble_metamorphic_resource_audit.json",
        "FOUNDRY_BABBLE_METAMORPHIC_RESOURCE_AUDIT_V1",
    )
    iteration29 = load(
        "readiness_iteration_2_9.json", "FOUNDRY_READINESS_ITERATION_2_9"
    )
    enumo_source_control = load(
        "phase45_enumo_source_control.json",
        "FOUNDRY_ENUMO_SOURCE_CONTROL_V1",
    )
    enumo_source_resource = load(
        "phase46_enumo_source_resource_audit.json",
        "FOUNDRY_ENUMO_SOURCE_RESOURCE_AUDIT_V1",
    )
    iteration30 = load(
        "readiness_iteration_3_0.json", "FOUNDRY_READINESS_ITERATION_3_0"
    )
    enumo_metamorphic = load(
        "phase47_enumo_metamorphic_control.json",
        "FOUNDRY_ENUMO_METAMORPHIC_CONTROL_V1",
    )
    enumo_metamorphic_resource = load(
        "phase48_enumo_metamorphic_resource_audit.json",
        "FOUNDRY_ENUMO_METAMORPHIC_RESOURCE_AUDIT_V1",
    )
    iteration31 = load(
        "readiness_iteration_3_1.json", "FOUNDRY_READINESS_ITERATION_3_1"
    )
    enumo_power = load(
        "phase49_enumo_power_diagnostic.json",
        "FOUNDRY_ENUMO_POWER_DIAGNOSTIC_V1",
    )
    enumo_power_resource = load(
        "phase50_enumo_power_resource_audit.json",
        "FOUNDRY_ENUMO_POWER_RESOURCE_AUDIT_V1",
    )
    iteration32 = load(
        "readiness_iteration_3_2.json", "FOUNDRY_READINESS_ITERATION_3_2"
    )
    control_four_audit = load(
        "phase51_control_four_route_audit.json",
        "FOUNDRY_CONTROL_FOUR_ROUTE_AUDIT_V1",
    )
    iteration33 = load(
        "readiness_iteration_3_3.json", "FOUNDRY_READINESS_ITERATION_3_3"
    )
    isamore_reduced_audit = load(
        "phase52_isamore_reduced_route_audit.json",
        "FOUNDRY_ISAMORE_REDUCED_ROUTE_AUDIT_V1",
    )
    iteration34 = load(
        "readiness_iteration_3_4.json", "FOUNDRY_READINESS_ITERATION_3_4"
    )
    diversity_audit = load(
        "phase53_diversity_calibration_audit.json",
        "FOUNDRY_DIVERSITY_CALIBRATION_AUDIT_V1",
    )
    diversity_resource = load(
        "phase54_diversity_calibration_resource_audit.json",
        "FOUNDRY_DIVERSITY_CALIBRATION_RESOURCE_AUDIT_V1",
    )
    iteration35 = load(
        "readiness_iteration_3_5.json", "FOUNDRY_READINESS_ITERATION_3_5"
    )
    diversity_forge = load(
        "phase55_diversity_tool_forge.json",
        "FOUNDRY_DIVERSITY_TOOL_FORGE_RESULT_V1",
    )
    diversity_conformance = load(
        "phase56_independent_diversity_conformance.json",
        "FOUNDRY_INDEPENDENT_DIVERSITY_CONFORMANCE_V1",
    )
    diversity_native = load(
        "phase57_diversity_native_dedup.json",
        "FOUNDRY_DIVERSITY_NATIVE_DEDUP_V1",
    )
    diversity_candidate_resource = load(
        "phase58_diversity_resource_audit.json",
        "FOUNDRY_DIVERSITY_RESOURCE_AUDIT_V1",
    )
    diversity_trial = load(
        "phase59_prospective_diversity_trial.json",
        "FOUNDRY_PROSPECTIVE_DIVERSITY_TRIAL_V1",
    )
    diversity_trial_resource = load(
        "phase60_prospective_diversity_resource_audit.json",
        "FOUNDRY_PROSPECTIVE_DIVERSITY_RESOURCE_AUDIT_V1",
    )
    iteration36 = load(
        "readiness_iteration_3_6.json", "FOUNDRY_READINESS_ITERATION_3_6"
    )
    diversity_failure = load(
        "phase61_diversity_failure_calibration.json",
        "FOUNDRY_DIVERSITY_FAILURE_CALIBRATION_V1",
    )
    diversity_failure_resource = load(
        "phase62_diversity_failure_resource_audit.json",
        "FOUNDRY_DIVERSITY_FAILURE_RESOURCE_AUDIT_V1",
    )
    iteration37 = load(
        "readiness_iteration_3_7.json", "FOUNDRY_READINESS_ITERATION_3_7"
    )
    pareto_calibration = load(
        "phase63_pareto_motif_calibration.json",
        "FOUNDRY_PARETO_MOTIF_CALIBRATION_V1",
    )
    pareto_optimizer = load(
        "phase64_pareto_portfolio_optimizer.json",
        "FOUNDRY_PARETO_PORTFOLIO_OPTIMIZER_V1",
    )
    pareto_conformance = load(
        "phase65_independent_pareto_conformance.json",
        "FOUNDRY_INDEPENDENT_PARETO_CONFORMANCE_V1",
    )
    pareto_native = load(
        "phase66_pareto_native_dedup.json",
        "FOUNDRY_PARETO_NATIVE_DEDUP_V1",
    )
    pareto_resource = load(
        "phase67_pareto_resource_audit.json",
        "FOUNDRY_PARETO_RESOURCE_AUDIT_V1",
    )
    pareto_authorization = load(
        "phase68_pareto_authorization_audit.json",
        "FOUNDRY_PARETO_AUTHORIZATION_AUDIT_V1",
    )
    authorization_access = load(
        "phase69_authorization_access_resource_audit.json",
        "FOUNDRY_AUTHORIZATION_ACCESS_RESOURCE_AUDIT_V1",
    )
    eggmind_source_route = load(
        "phase70_eggmind_source_route_audit.json",
        "FOUNDRY_EGGMIND_SOURCE_ROUTE_AUDIT_V1",
    )
    eggmind_boundary = load(
        "phase71_eggmind_adapted_boundary_conformance.json",
        "FOUNDRY_EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_V1",
    )
    per_instance_controls = load(
        "phase72_per_instance_control_conformance.json",
        "FOUNDRY_PER_INSTANCE_CONTROL_CONFORMANCE_V1",
    )
    per_instance_resource = load(
        "phase73_per_instance_resource_audit.json",
        "FOUNDRY_PER_INSTANCE_RESOURCE_AUDIT_V1",
    )
    iteration38 = load(
        "readiness_iteration_3_8.json", "FOUNDRY_READINESS_ITERATION_3_8"
    )
    iteration39 = load(
        "readiness_iteration_3_9.json", "FOUNDRY_READINESS_ITERATION_3_9"
    )
    external_invocation_trace = load(
        "phase74_external_invocation_trace_audit.json",
        "FOUNDRY_EXTERNAL_INVOCATION_TRACE_AUDIT_V1",
    )
    external_trace_replay = load(
        "phase75_external_trace_independent_replay.json",
        "FOUNDRY_EXTERNAL_TRACE_INDEPENDENT_REPLAY_V1",
    )
    external_horizon_sensitivity = load(
        "phase76_external_horizon_sensitivity.json",
        "FOUNDRY_EXTERNAL_HORIZON_SENSITIVITY_V1",
    )
    iteration40 = load(
        "readiness_iteration_4_0.json", "FOUNDRY_READINESS_ITERATION_4_0"
    )
    local_trace_provenance = load(
        "phase77_local_trace_provenance.json",
        "FOUNDRY_LOCAL_TRACE_PROVENANCE_V1",
    )
    offline_trace_replay = load(
        "phase78_offline_trace_replay.json",
        "FOUNDRY_OFFLINE_TRACE_REPLAY_V1",
    )
    offline_trace_resource = load(
        "phase79_offline_trace_resource_audit.json",
        "FOUNDRY_OFFLINE_TRACE_RESOURCE_AUDIT_V1",
    )
    horizon_unit_mapping = load(
        "phase80_horizon_unit_mapping_audit.json",
        "FOUNDRY_HORIZON_UNIT_MAPPING_AUDIT_V1",
    )
    horizon_clarification = load(
        "phase81_horizon_clarification_conformance.json",
        "FOUNDRY_HORIZON_CLARIFICATION_CONFORMANCE_V1",
    )
    horizon_protocol_resource = load(
        "phase82_horizon_protocol_resource_audit.json",
        "FOUNDRY_HORIZON_PROTOCOL_RESOURCE_AUDIT_V1",
    )
    iteration41 = load(
        "readiness_iteration_4_1.json", "FOUNDRY_READINESS_ITERATION_4_1"
    )
    arm_adapter_conformance = load(
        "phase83_arm_adapter_contract_conformance.json",
        "FOUNDRY_ARM_ADAPTER_CONFORMANCE_V1",
    )
    arm_adapter_resource = load(
        "phase84_arm_adapter_contract_resource_audit.json",
        "FOUNDRY_ARM_ADAPTER_RESOURCE_AUDIT_V1",
    )
    iteration42 = load(
        "readiness_iteration_4_2.json", "FOUNDRY_READINESS_ITERATION_4_2"
    )
    state_reset_adapter = load(
        "phase85_state_reset_adapter_conformance.json",
        "FOUNDRY_STATE_RESET_ADAPTER_CONFORMANCE_V1",
    )
    state_reset_resource = load(
        "phase86_state_reset_adapter_resource_audit.json",
        "FOUNDRY_STATE_RESET_ADAPTER_RESOURCE_AUDIT_V1",
    )
    iteration43 = load(
        "readiness_iteration_4_3.json", "FOUNDRY_READINESS_ITERATION_4_3"
    )
    operator_vocab = load(
        "phase87_calibration_operator_vocabulary_audit.json",
        "FOUNDRY_CALIBRATION_OPERATOR_VOCAB_AUDIT_V1",
    )
    operator_vocab_resource = load(
        "phase88_calibration_operator_vocabulary_resource_audit.json",
        "FOUNDRY_CALIBRATION_OPERATOR_VOCAB_RESOURCE_AUDIT_V1",
    )
    iteration44 = load(
        "readiness_iteration_4_4.json", "FOUNDRY_READINESS_ITERATION_4_4"
    )
    framework_mount = load(
        "phase89_framework_runtime_mount_conformance.json",
        "FOUNDRY_FRAMEWORK_RUNTIME_MOUNT_CONFORMANCE_V1",
    )
    framework_mount_resource = load(
        "phase90_framework_runtime_mount_resource_audit.json",
        "FOUNDRY_FRAMEWORK_RUNTIME_MOUNT_RESOURCE_AUDIT_V1",
    )
    iteration45 = load(
        "readiness_iteration_4_5.json", "FOUNDRY_READINESS_ITERATION_4_5"
    )
    shared_resource_batch = load(
        "phase91_shared_resource_batch_conformance.json",
        "FOUNDRY_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
    )
    shared_resource_batch_resource = load(
        "phase92_shared_resource_batch_resource_audit.json",
        "FOUNDRY_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
    )
    iteration46 = load(
        "readiness_iteration_4_6.json", "FOUNDRY_READINESS_ITERATION_4_6"
    )
    a1_compatibility = load(
        "phase93_a1_ir_compatibility_audit.json",
        "FOUNDRY_A1_IR_COMPATIBILITY_AUDIT_V1",
    )
    a1_compatibility_resource = load(
        "phase94_a1_ir_compatibility_resource_audit.json",
        "FOUNDRY_A1_IR_COMPATIBILITY_RESOURCE_AUDIT_V1",
    )
    iteration47 = load(
        "readiness_iteration_4_7.json", "FOUNDRY_READINESS_ITERATION_4_7"
    )
    a4_replay = load(
        "phase95_a4_replay_runtime_conformance.json",
        "FOUNDRY_A4_REPLAY_RUNTIME_CONFORMANCE_V1",
    )
    a4_replay_resource = load(
        "phase96_a4_replay_runtime_resource_audit.json",
        "FOUNDRY_A4_REPLAY_RUNTIME_RESOURCE_AUDIT_V1",
    )
    a4_batch = load(
        "phase97_a4_shared_resource_batch_conformance.json",
        "FOUNDRY_A4_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
    )
    a4_batch_resource = load(
        "phase98_a4_shared_resource_batch_resource_audit.json",
        "FOUNDRY_A4_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
    )
    iteration48 = load(
        "readiness_iteration_4_8.json", "FOUNDRY_READINESS_ITERATION_4_8"
    )
    a5_typed = load(
        "phase99_a5_stitch_typed_graph_audit.json",
        "FOUNDRY_A5_STITCH_TYPED_GRAPH_AUDIT_V1",
    )
    a5_typed_resource = load(
        "phase100_a5_stitch_typed_graph_resource_audit.json",
        "FOUNDRY_A5_STITCH_TYPED_GRAPH_RESOURCE_AUDIT_V1",
    )
    a5_mount = load(
        "phase101_a5_stitch_runtime_conformance.json",
        "FOUNDRY_A5_STITCH_RUNTIME_CONFORMANCE_V1",
    )
    a5_mount_resource = load(
        "phase102_a5_stitch_runtime_resource_audit.json",
        "FOUNDRY_A5_STITCH_RUNTIME_RESOURCE_AUDIT_V1",
    )
    a5_batch = load(
        "phase103_a5_shared_resource_batch_conformance.json",
        "FOUNDRY_A5_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
    )
    a5_batch_resource = load(
        "phase104_a5_shared_resource_batch_resource_audit.json",
        "FOUNDRY_A5_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
    )
    iteration49 = load(
        "readiness_iteration_4_9.json", "FOUNDRY_READINESS_ITERATION_4_9"
    )
    a7_compatibility = load(
        "phase105_a7_enumo_compatibility_audit.json",
        "FOUNDRY_A7_ENUMO_COMPATIBILITY_AUDIT_V1",
    )
    a7_compatibility_resource = load(
        "phase106_a7_enumo_compatibility_resource_audit.json",
        "FOUNDRY_A7_ENUMO_COMPATIBILITY_RESOURCE_AUDIT_V1",
    )
    iteration50 = load(
        "readiness_iteration_5_0.json", "FOUNDRY_READINESS_ITERATION_5_0"
    )
    unsupported_matrix = load(
        "phase107_required_unsupported_matrix_audit.json",
        "FOUNDRY_REQUIRED_UNSUPPORTED_MATRIX_AUDIT_V1",
    )
    unsupported_matrix_resource = load(
        "phase108_required_unsupported_matrix_resource_audit.json",
        "FOUNDRY_REQUIRED_UNSUPPORTED_MATRIX_RESOURCE_AUDIT_V1",
    )
    unsupported_contract = load(
        "phase109_required_unsupported_contract_conformance.json",
        "FOUNDRY_REQUIRED_UNSUPPORTED_CONTRACT_CONFORMANCE_V1",
    )
    unsupported_contract_resource = load(
        "phase110_required_unsupported_contract_resource_audit.json",
        "FOUNDRY_REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE_AUDIT_V1",
    )
    iteration51 = load(
        "readiness_iteration_5_1.json", "FOUNDRY_READINESS_ITERATION_5_1"
    )
    isamore_acquisition = load(
        "phase111_isamore_recursive_source_acquisition.json",
        "FOUNDRY_ISAMORE_RECURSIVE_SOURCE_ACQUISITION_V2",
    )
    isamore_build = load(
        "phase112_isamore_offline_build_closure.json",
        "FOUNDRY_ISAMORE_OFFLINE_BUILD_CLOSURE_V1",
    )
    iteration52 = load(
        "readiness_iteration_5_2.json", "FOUNDRY_READINESS_ITERATION_5_2"
    )
    isamore_colored_bridge = load(
        "phase113_isamore_colored_bridge_audit.json",
        "FOUNDRY_ISAMORE_COLORED_BRIDGE_AUDIT_V1",
    )
    iteration53 = load(
        "readiness_iteration_5_3.json", "FOUNDRY_READINESS_ITERATION_5_3"
    )
    isamore_crossbeam_bridge = load(
        "phase114_isamore_crossbeam_bridge_audit.json",
        "FOUNDRY_ISAMORE_CROSSBEAM_BRIDGE_AUDIT_V1",
    )
    iteration54 = load(
        "readiness_iteration_5_4.json", "FOUNDRY_READINESS_ITERATION_5_4"
    )
    isamore_csv_closure = load(
        "phase115_isamore_csv_closure_census.json",
        "FOUNDRY_ISAMORE_CSV_CLOSURE_CENSUS_V1",
    )
    iteration55 = load(
        "readiness_iteration_5_5.json", "FOUNDRY_READINESS_ITERATION_5_5"
    )
    isamore_csv_tag_bridge = load(
        "phase116_isamore_csv_tag_bridge_audit.json",
        "FOUNDRY_ISAMORE_CSV_TAG_BRIDGE_AUDIT_V1",
    )
    iteration56 = load(
        "readiness_iteration_5_6.json", "FOUNDRY_READINESS_ITERATION_5_6"
    )
    isamore_env_logger_closure = load(
        "phase117_isamore_env_logger_closure_census.json",
        "FOUNDRY_ISAMORE_ENV_LOGGER_CLOSURE_CENSUS_V1",
    )
    iteration57 = load(
        "readiness_iteration_5_7.json", "FOUNDRY_READINESS_ITERATION_5_7"
    )
    isamore_env_logger_roots = load(
        "phase118_isamore_env_logger_roots_bridge_audit.json",
        "FOUNDRY_ISAMORE_ENV_LOGGER_ROOTS_BRIDGE_AUDIT_V1",
    )
    iteration58 = load(
        "readiness_iteration_5_8.json", "FOUNDRY_READINESS_ITERATION_5_8"
    )
    isamore_graphviz_closure = load(
        "phase119_isamore_graphviz_closure_census.json",
        "FOUNDRY_ISAMORE_GRAPHVIZ_CLOSURE_CENSUS_V1",
    )
    iteration59 = load(
        "readiness_iteration_5_9.json", "FOUNDRY_READINESS_ITERATION_5_9"
    )
    isamore_graphviz_bridge = load(
        "phase120_isamore_graphviz_family_bridge_audit.json",
        "FOUNDRY_ISAMORE_GRAPHVIZ_FAMILY_BRIDGE_AUDIT_V1",
    )
    iteration510 = load(
        "readiness_iteration_5_10.json", "FOUNDRY_READINESS_ITERATION_5_10"
    )
    isamore_indicatif_closure = load(
        "phase121_isamore_indicatif_closure_census.json",
        "FOUNDRY_ISAMORE_INDICATIF_CLOSURE_CENSUS_V1",
    )
    iteration511 = load(
        "readiness_iteration_5_11.json", "FOUNDRY_READINESS_ITERATION_5_11"
    )
    isamore_indicatif_bridge = load(
        "phase122_isamore_indicatif_family_bridge_audit.json",
        "FOUNDRY_ISAMORE_INDICATIF_FAMILY_BRIDGE_AUDIT_V1",
    )
    iteration512 = load(
        "readiness_iteration_5_12.json", "FOUNDRY_READINESS_ITERATION_5_12"
    )
    isamore_kiddo_closure = load(
        "phase123_isamore_kiddo_closure_census.json",
        "FOUNDRY_ISAMORE_KIDDO_CLOSURE_CENSUS_V1",
    )
    iteration513 = load(
        "readiness_iteration_5_13.json", "FOUNDRY_READINESS_ITERATION_5_13"
    )
    isamore_kiddo_partial_bridge = load(
        "phase124_isamore_kiddo_partial_family_bridge_audit.json",
        "FOUNDRY_ISAMORE_KIDDO_PARTIAL_FAMILY_BRIDGE_AUDIT_V1",
    )
    iteration514 = load(
        "readiness_iteration_5_14.json", "FOUNDRY_READINESS_ITERATION_5_14"
    )
    isamore_kiddo_root_acquisition = load(
        "phase125_isamore_kiddo_root_acquisition_channel_audit.json",
        "FOUNDRY_ISAMORE_KIDDO_ROOT_ACQUISITION_CHANNEL_AUDIT_V1",
    )
    iteration515 = load(
        "readiness_iteration_5_15.json", "FOUNDRY_READINESS_ITERATION_5_15"
    )
    isamore_divrem_bridge = load(
        "phase126_isamore_divrem_family_bridge_audit.json",
        "FOUNDRY_ISAMORE_DIVREM_FAMILY_BRIDGE_AUDIT_V1",
    )
    iteration516 = load(
        "readiness_iteration_5_16.json", "FOUNDRY_READINESS_ITERATION_5_16"
    )
    isamore_remaining_math_channels = load(
        "phase127_isamore_remaining_math_source_channel_audit.json",
        "FOUNDRY_ISAMORE_REMAINING_MATH_SOURCE_CHANNEL_AUDIT_V1",
    )
    iteration517 = load(
        "readiness_iteration_5_17.json", "FOUNDRY_READINESS_ITERATION_5_17"
    )
    isamore_coin_cbc_bindings = load(
        "phase128_isamore_coin_cbc_binding_bridge_audit.json",
        "FOUNDRY_ISAMORE_COIN_CBC_BINDING_BRIDGE_AUDIT_V1",
    )
    iteration518 = load(
        "readiness_iteration_5_18.json", "FOUNDRY_READINESS_ITERATION_5_18"
    )
    isamore_native_lp_acquisition = load(
        "phase129_isamore_native_lp_acquisition_channel_audit.json",
        "FOUNDRY_ISAMORE_NATIVE_LP_ACQUISITION_CHANNEL_AUDIT_V1",
    )
    iteration519 = load(
        "readiness_iteration_5_19.json", "FOUNDRY_READINESS_ITERATION_5_19"
    )
    isamore_archive_transport = load(
        "phase130_isamore_exact_archive_transport_recovery_audit.json",
        "FOUNDRY_ISAMORE_EXACT_ARCHIVE_TRANSPORT_RECOVERY_AUDIT_V1",
    )
    a1_reference_no_go = load(
        "phase131_a1_reference_fallback_no_go_audit.json",
        "FOUNDRY_A1_REFERENCE_FALLBACK_NO_GO_AUDIT_V1",
    )
    iteration520 = load(
        "readiness_iteration_5_20.json", "FOUNDRY_READINESS_ITERATION_5_20"
    )
    enumo_tensor_feasibility = load(
        "phase132_enumo_tensor_domain_feasibility.json",
        "FOUNDRY_ENUMO_TENSOR_DOMAIN_FEASIBILITY_RESULT_V1",
    )
    enumo_tensor_rule_reuse = load(
        "phase133_enumo_tensor_rule_reuse_competitiveness.json",
        "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_RESULT_V1",
    )
    iteration521 = load(
        "readiness_iteration_5_21.json", "FOUNDRY_READINESS_ITERATION_5_21"
    )
    pareto_v08_search_distinction = load(
        "phase134_v08_search_distinction_conformance.json",
        "FOUNDRY_V08_SEARCH_DISTINCTION_CONFORMANCE_V1",
    )
    iteration522 = load(
        "readiness_iteration_5_22.json", "FOUNDRY_READINESS_ITERATION_5_22"
    )
    eggmind_reproduction_sufficiency = load(
        "phase135_eggmind_full_reproduction_sufficiency_audit.json",
        "FOUNDRY_EGGMIND_FULL_REPRODUCTION_SUFFICIENCY_AUDIT_V1",
    )
    isamore_exact_artifact_ingress = load(
        "phase136_isamore_exact_artifact_ingress_conformance.json",
        "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_V1",
    )
    iteration523 = load(
        "readiness_iteration_5_23.json", "FOUNDRY_READINESS_ITERATION_5_23"
    )
    sympy_cse_source_control = load(
        "phase137_sympy_cse_source_control.json",
        "FOUNDRY_SYMPY_CSE_SOURCE_CONTROL_V1",
    )
    sympy_cse_conformance = load(
        "phase138_sympy_cse_independent_resource_conformance.json",
        "FOUNDRY_SYMPY_CSE_INDEPENDENT_RESOURCE_CONFORMANCE_V1",
    )
    iteration524 = load(
        "readiness_iteration_5_24.json", "FOUNDRY_READINESS_ITERATION_5_24"
    )
    missing_arm_closure = load(
        "phase139_missing_arm_closure_audit.json",
        "FOUNDRY_MISSING_ARM_CLOSURE_AUDIT_V1",
    )
    a7_real_transfer = load(
        "phase140_a7_enumo_real_graph_transfer.json",
        "FOUNDRY_A7_ENUMO_REAL_GRAPH_TRANSFER_RESULT_V1",
    )
    a7_runtime_mount = load(
        "phase141_a7_enumo_runtime_conformance.json",
        "FOUNDRY_A7_ENUMO_RUNTIME_CONFORMANCE_V1",
    )
    a7_runtime_resource = load(
        "phase142_a7_enumo_runtime_resource_audit.json",
        "FOUNDRY_A7_ENUMO_RUNTIME_RESOURCE_AUDIT_V1",
    )
    a7_batch = load(
        "phase143_a7_shared_resource_batch_conformance.json",
        "FOUNDRY_A7_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
    )
    a7_batch_resource = load(
        "phase144_a7_shared_resource_batch_resource_audit.json",
        "FOUNDRY_A7_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
    )
    iteration525 = load(
        "readiness_iteration_5_25.json", "FOUNDRY_READINESS_ITERATION_5_25"
    )
    a1_subgraph_reachability = load(
        "phase145_a1_subgraph_constructor_reachability.json",
        "FOUNDRY_A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_RESULT_V1",
    )
    iteration526 = load(
        "readiness_iteration_5_26.json", "FOUNDRY_READINESS_ITERATION_5_26"
    )
    a1_subgraph_reachability_corrected = load(
        "phase145_a1_subgraph_constructor_reachability_corrected.json",
        "FOUNDRY_A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_RESULT_V1",
    )
    iteration527 = load(
        "readiness_iteration_5_27.json", "FOUNDRY_READINESS_ITERATION_5_27"
    )
    a1_fold_failed_conformance = load(
        "phase146_a1_pattern_first_fold_conformance.json",
        "FOUNDRY_A1_PATTERN_FIRST_FOLD_RESULT_V1",
    )
    a1_numerical_remediation = load(
        "phase147_a1_fold_numerical_stability_remediation.json",
        "FOUNDRY_A1_FOLD_NUMERICAL_STABILITY_RESULT_V1",
    )
    a1_full_runtime_contract = load(
        "phase148_a1_full_runtime_contract_batch.json",
        "FOUNDRY_A1_FULL_RUNTIME_CONTRACT_RESULT_V1",
    )
    iteration528 = load(
        "readiness_iteration_5_28.json", "FOUNDRY_READINESS_ITERATION_5_28"
    )
    a6_reachability = load(
        "phase149_a6_typed_anti_unification_reachability.json",
        "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_REACHABILITY_RESULT_V1",
    )
    a6_runtime_contract = load(
        "phase151_a6_typed_anti_unification_runtime_contract.json",
        "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_RUNTIME_CONTRACT_V1",
    )
    iteration529 = load(
        "readiness_iteration_5_29.json", "FOUNDRY_READINESS_ITERATION_5_29"
    )
    a8_reachability = load(
        "phase152_a8_adapted_strategy_reachability.json",
        "FOUNDRY_A8_ADAPTED_STRATEGY_REACHABILITY_RESULT_V1",
    )
    a8_runtime_contract = load(
        "phase153_a8_adapted_strategy_runtime_contract.json",
        "FOUNDRY_A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_V1",
    )
    v6_access_incident = load(
        "phase154_validation_v6_pre_authorization_access_incident.json",
        "FOUNDRY_VALIDATION_V6_PREAUTH_ACCESS_INCIDENT_V1",
    )
    iteration530 = load(
        "readiness_iteration_5_30.json", "FOUNDRY_READINESS_ITERATION_5_30"
    )
    validation_v7_intake = load(
        "phase155_validation_v7_identity_only_intake.json",
        "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_RESULT_V1",
    )
    iteration531 = load(
        "readiness_iteration_5_31.json", "FOUNDRY_READINESS_ITERATION_5_31"
    )
    validation_v7_privacy_audit = load(
        "phase156_validation_v7_identity_privacy_audit.json",
        "FOUNDRY_VALIDATION_V7_IDENTITY_PRIVACY_AUDIT_RESULT_V1",
    )
    validation_v7_intake_v2 = load(
        "phase157_validation_v7_identity_only_intake_v2.json",
        "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_RESULT_V1",
    )
    iteration532 = load(
        "readiness_iteration_5_32.json", "FOUNDRY_READINESS_ITERATION_5_32"
    )
    validation_v7_provenance_v1_audit = load(
        "phase158_validation_v7_provenance_v1_enforcement_audit.json",
        "FOUNDRY_VALIDATION_V7_PROVENANCE_V1_ENFORCEMENT_AUDIT_V1",
    )
    validation_v7_provenance_v2 = load(
        "phase159_validation_v7_accountable_provenance_v2.json",
        "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_V2_RESULT_V1",
    )
    iteration533 = load(
        "readiness_iteration_5_33.json", "FOUNDRY_READINESS_ITERATION_5_33"
    )
    local_grammar = load(
        "phase160_local_grammar_emergence.json",
        "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_RESULT_V1",
    )
    local_template = load(
        "phase161_local_typed_template_transfer.json",
        "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_RESULT_V1",
    )
    local_informativeness = load(
        "phase162_local_template_informativeness.json",
        "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_RESULT_V1",
    )
    iteration534 = load(
        "readiness_iteration_5_34.json", "FOUNDRY_READINESS_ITERATION_5_34"
    )
    local_operator_prediction = load(
        "phase163_local_operator_prediction.json",
        "FOUNDRY_LOCAL_OPERATOR_PREDICTION_RESULT_V1",
    )
    local_exact_body_prediction = load(
        "phase164_local_exact_body_prediction.json",
        "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_RESULT_V1",
    )
    local_exact_tool_execution = load(
        "phase165_local_exact_tool_execution.json",
        "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_RESULT_V1",
    )
    iteration535 = load(
        "readiness_iteration_5_35.json", "FOUNDRY_READINESS_ITERATION_5_35"
    )
    local_exact_tool_utility = load(
        "phase166_local_exact_tool_utility.json",
        "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_RESULT_V1",
    )
    iteration536 = load(
        "readiness_iteration_5_36.json", "FOUNDRY_READINESS_ITERATION_5_36"
    )
    goal_continuation536 = load(
        "goal_continuation_audit_5_36.json",
        "FOUNDRY_GOAL_CONTINUATION_AUDIT_5_36",
    )
    parse_diversity_library(
        (RESULTS / "forged_diversity_tools.json").read_bytes()
    )
    parse_pareto_library(
        (RESULTS / "forged_pareto_tools.json").read_bytes()
    )
    library = json.loads((RESULTS / "learned_tools.json").read_text(encoding="utf-8"))
    require(len(library["tools"]) == 4, "learned library does not have four tools")
    for tool in library["tools"].values():
        parse_tool(tool)

    p1 = phase1["pilot"]["summary"]
    p2 = phase2["phase2"]["summary"]
    require(p1["candidate_exact"] == p1["fixed_exact"] == p1["tasks"] == 4, "phase1 evidence changed")
    require(p2["candidate_exact"] == p2["fixed_exact"] == p2["tasks"] == 4, "phase2 evidence changed")
    require(p2["causal_removal_losses"] == 4, "causal removal evidence changed")
    require(readiness["verdict"] == "FOUNDRY_V6_NOT_READY", "base verdict is not fail-closed")
    require(readiness["gates_passed"] == 8 and readiness["gates_total"] == 9, "mechanism gates changed")
    require(remediation["status"] == "EXECUTED_VALID_NEGATIVE", "remediation not preserved")

    ds = dedup["summary"]
    require(ds["plans"] == 24 and ds["representative_signatures"] == 11, "dedup coverage changed")
    require(
        ds["inductor_receipts_completed"] + ds["inductor_required_unsupported"] == 11,
        "dedup representatives lack explicit outcomes",
    )
    require(iteration11["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.1 inflated verdict")

    cs = corpus["summary"]
    require(cs["examples"] == 36 and cs["exported"] == 32, "external corpus intake changed")
    require(corpus["P2"]["complete"] is False, "P2 prematurely completed")
    require(iteration12["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.2 inflated verdict")
    require(intake["repository_records_pinned"] == 3, "control source intake changed")
    require(intake["conformance_executed"] == 0, "unexecuted conformance marked complete")
    require(iteration13["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.3 inflated verdict")
    require(
        resource_audit["status"] == "RESOURCE_COMPONENT_READY",
        "process-tree resource component is not ready",
    )
    require(
        resource_audit["P3"]["representative_local_arms_integrated"] is True,
        "representative local arms are not metered",
    )
    require(resource_audit["P3"]["complete"] is False, "P3 prematurely completed")
    require(iteration14["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.4 inflated verdict")
    admission_summary = admission["summary"]
    require(admission_summary["plans"] == 24, "future-tool admission coverage changed")
    require(
        admission_summary["REJECT_NATIVE_DUPLICATE"]
        + admission_summary["QUARANTINE_UNRESOLVED"]
        == admission_summary["plans"],
        "future-tool admission has an unclassified plan",
    )
    require(admission_summary["ADMIT"] == 0, "unproven v5.1 seed tool was admitted")
    require(
        admission["P5"]["future_candidate_audit_executed"] is False,
        "retrospective v5.1 policy was mislabeled as a future candidate audit",
    )
    require(admission["P5"]["complete"] is False, "P5 prematurely completed")
    require(iteration15["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.5 inflated verdict")
    require(
        tensor_forge["status"] == "TENSOR_FORGE_COMPONENT_READY"
        and tensor_forge["tools_forged"] == 4
        and tensor_forge["support_total"] == 19,
        "typed tensor forge evidence changed",
    )
    require(
        tensor_eval["status"] == "INDEPENDENT_TENSOR_TOOL_EVAL_PASS"
        and tensor_eval["tools"] == 4
        and tensor_eval["successful_transfers"] == 20
        and len(tensor_eval["hostile_rejections"]) == 4,
        "independent tensor-tool evidence changed",
    )
    require(
        tensor_native["status"] == "TENSOR_NATIVE_RESOURCE_COMPONENT_READY"
        and tensor_native["P3"]["new_tensor_forge_arms_integrated"] is True
        and tensor_native["P5"]["current_candidates_classified"] is True,
        "tensor native/resource audit is incomplete",
    )
    require(tensor_native["P3"]["complete"] is False, "P3 prematurely completed")
    require(tensor_native["P5"]["complete"] is False, "P5 prematurely completed")
    require(tensor_native["P5"]["admitted"] == 0, "unproven tensor tool was admitted")
    require(iteration16["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.6 inflated verdict")
    require(
        len(tensor_component_freeze["records"]) == 16
        and tensor_component_freeze["boundary"]["prospective_trial_authorized"] is False,
        "tensor component freeze boundary changed",
    )
    require(iteration17["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.7 inflated verdict")
    require(
        len(external_intake_freeze["records"]) == 7
        and external_intake_freeze["execution_observed"] is False,
        "external application intake was not pre-execution frozen",
    )
    require(
        external_trace["status"] == "EXTERNAL_APPLICATION_TRACE_COMPONENT_READY"
        and external_trace["summary"]["families"] == 4
        and external_trace["summary"]["traced"] == 4
        and external_trace["summary"]["exported"] == 4,
        "external application trace evidence changed",
    )
    require(
        reachability["status"] == "EXTERNAL_TOOL_REACHABILITY_VALID_NEGATIVE"
        and reachability["pairs"] == 16
        and reachability["coarse_reachable_pairs"] == 0,
        "external reachability negative changed",
    )
    require(reachability["P2"]["complete"] is False, "P2 prematurely completed")
    require(iteration18["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.8 inflated verdict")
    require(
        len(external_validation_freeze["records"]) == 7
        and external_validation_freeze["boundary"]["aten_forge_output_observed"] is False
        and external_validation_freeze["boundary"]["validation_execution_observed"] is False,
        "ATen validation source boundary changed",
    )
    require(
        aten_forge["status"] == "ATEN_FORGE_COMPONENT_READY"
        and aten_forge["candidate_patterns"] == 46
        and aten_forge["tools_forged"] == 6
        and aten_forge["selected_description_length_gain"] == 15,
        "ATen forge evidence changed",
    )
    require(
        aten_eval["status"] == "INDEPENDENT_ATEN_EVAL_TRANSFER_PASS"
        and aten_eval["tools"] == 6
        and aten_eval["matched_tools"] == 1
        and aten_eval["successful_macro_replays"] == 1
        and len(aten_eval["hostile_rejections"]) == 4
        and aten_eval["prospective_boundary"]["classification"]
        == "CALIBRATION_ONLY_ADVERSARIAL_PILOT",
        "independent ATen evaluation evidence changed",
    )
    require(
        aten_audit["status"] == "ATEN_RESOURCE_COMPONENT_READY"
        and aten_audit["summary"]["tools"] == 6
        and aten_audit["summary"]["quarantined"] == 6
        and aten_audit["summary"]["admitted"] == 0
        and aten_audit["P3"]["complete"] is False
        and aten_audit["P5"]["complete"] is False,
        "ATen resource/native classification changed",
    )
    require(iteration19["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 1.9 inflated verdict")
    require(
        len(aten_v2_freeze["records"]) == 17
        and aten_v2_freeze["boundary"]["v2_execution_observed"] is False
        and aten_v2_freeze["boundary"]["runtime_harness_frozen"] is True,
        "prospective-v2 base freeze changed",
    )
    require(
        len(aten_v21_freeze["records"]) == 6
        and aten_v21_freeze["boundary"]["candidate_outcomes_observed"] is False
        and aten_v21_freeze["boundary"]["permitted_change"] == "METER_API_ONLY",
        "prospective-v2.1 remediation boundary changed",
    )
    require(
        len(aten_v22_freeze["records"]) == 10
        and aten_v22_freeze["boundary"]["candidate_outcomes_observed"] is False
        and aten_v22_freeze["boundary"]["permitted_change"]
        == "DEPENDENCY_ISOLATION_ONLY",
        "prospective-v2.2 remediation boundary changed",
    )
    require(
        prospective_infra["status"] == "PROSPECTIVE_V2_INFRASTRUCTURE_FAILURE"
        and prospective_infra["candidate_outcomes_observed"] is False,
        "initial prospective infrastructure failure changed",
    )
    require(
        prospective_v21_resource["status"] == "PROSPECTIVE_RESOURCE_FAIL"
        and prospective_v21_resource["receipt"]["returncode"] == 1
        and prospective_v21_resource["receipt"]["termination"] == "natural",
        "prospective-v2.1 dependency failure changed",
    )
    require(
        prospective_v22["status"] == "PROSPECTIVE_COMPONENT_VALID_NEGATIVE"
        and prospective_v22["supported_families"] == 3
        and prospective_v22["ledgers"]["candidate"]["matches"] == 1
        and prospective_v22["ledgers"]["fixed"]["matches"] == 1
        and prospective_v22["ledgers"]["candidate"]["total_cost"] == 175
        and prospective_v22["ledgers"]["fixed"]["total_cost"] == 235
        and prospective_v22["P2_component_complete"] is False
        and prospective_v22["P5_runtime_invention_admitted"] == 0,
        "prospective-v2.2 result changed",
    )
    require(
        prospective_v22_resource["status"] == "PROSPECTIVE_RESOURCE_PASS"
        and prospective_v22_resource["P3_component_metered"] is True
        and prospective_v22_resource["P3_complete"] is False,
        "prospective-v2.2 resource evidence changed",
    )
    require(iteration20["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.0 inflated verdict")
    require(
        len(semantic_prefreeze["records"]) == 23
        and semantic_prefreeze["boundary"]["semantic_forge_executed"] is False
        and semantic_prefreeze["boundary"]["semantic_tool_records_observed"] is False
        and semantic_prefreeze["boundary"]["supplied_tool_forms"] == 0,
        "semantic prospective boundary changed",
    )
    require(
        len(semantic_result_freeze["records"]) == 7
        and semantic_result_freeze["classification"]
        == "PROSPECTIVE_VALID_NEGATIVE",
        "semantic result freeze changed",
    )
    require(
        semantic_forge["status"] == "SEMANTIC_GRAMMAR_FORGE_READY"
        and semantic_forge["candidate_patterns"] == 31
        and semantic_forge["tools_forged"] == 3
        and semantic_forge["description_length_gain"] == 11
        and semantic_forge["autonomy_boundary"]["llm_calls"] == 0
        and semantic_forge["autonomy_boundary"]["supplied_tool_forms"] == 0,
        "semantic forge evidence changed",
    )
    require(
        semantic_eval["status"] == "SEMANTIC_PROSPECTIVE_VALID_NEGATIVE"
        and semantic_eval["families"] == 4
        and semantic_eval["tools"] == 3
        and semantic_eval["matched_tools"] == 0
        and semantic_eval["successful_replays"] == 0
        and len(semantic_eval["hostile_rejections"]) == 5
        and semantic_eval["candidate"]["total_cost"] == 95
        and semantic_eval["fixed"]["total_cost"] == 234
        and semantic_eval["fixed"]["matches"] == 4,
        "semantic prospective evaluation changed",
    )
    require(
        semantic_native["status"] == "SEMANTIC_NATIVE_DEDUP_COMPLETE"
        and semantic_native["summary"]["tools"] == 3
        and semantic_native["summary"]["stock_decomposition_duplicates"] == 3
        and semantic_native["summary"]["required_unsupported"] == 3
        and semantic_native["summary"]["admitted"] == 0,
        "semantic native audit changed",
    )
    require(
        semantic_resource["status"] == "SEMANTIC_RESOURCE_COMPONENT_READY"
        and semantic_resource["P3"]["semantic_forge_matrix_integrated"] is True
        and semantic_resource["P3"]["complete"] is False,
        "semantic resource matrix changed",
    )
    require(iteration21["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.1 inflated verdict")
    require(
        len(external_validation_v4_freeze["records"]) == 10,
        "external validation-v4 freeze changed",
    )
    require(
        len(polymorphic_prefreeze["records"]) == 14
        and polymorphic_prefreeze["boundary"]["polymorphic_forge_executed"]
        is False
        and polymorphic_prefreeze["boundary"][
            "polymorphic_tool_records_observed"
        ]
        is False
        and polymorphic_prefreeze["boundary"]["validation_execution_observed"]
        is False
        and polymorphic_prefreeze["boundary"]["llm_calls_allowed"] == 0
        and polymorphic_prefreeze["boundary"][
            "manual_type_widenings_allowed"
        ]
        == 0,
        "polymorphic prospective boundary changed",
    )
    require(
        len(polymorphic_result_freeze["records"]) == 7
        and polymorphic_result_freeze["classification"]
        == "PROSPECTIVE_VALID_NEGATIVE",
        "polymorphic result freeze changed",
    )
    require(
        polymorphic_forge["status"] == "POLYMORPHIC_SEMANTIC_FORGE_READY"
        and polymorphic_forge["tools"] == 3
        and polymorphic_forge["generalized_input_constraints"] == 5
        and polymorphic_forge["generalized_output_constraints"] == 0
        and polymorphic_forge["autonomy_boundary"]["llm_calls"] == 0
        and polymorphic_forge["autonomy_boundary"]["manual_type_widenings"]
        == 0
        and polymorphic_forge["autonomy_boundary"]["validation_accessed"]
        is False
        and polymorphic_forge["autonomy_boundary"][
            "all_allowed_signatures_observed"
        ]
        is True,
        "polymorphic forge evidence changed",
    )
    require(
        polymorphic_eval["status"]
        == "POLYMORPHIC_PROSPECTIVE_VALID_NEGATIVE"
        and polymorphic_eval["families"] == 4
        and polymorphic_eval["tools"] == 3
        and polymorphic_eval["matched_tools"] == 3
        and polymorphic_eval["matched_families"] == 1
        and polymorphic_eval["successful_replays"] == 3
        and len(polymorphic_eval["hostile_rejections"]) == 6
        and polymorphic_eval["candidate"]["benefit"] == 7
        and polymorphic_eval["fixed"]["benefit"] == 14
        and polymorphic_eval["candidate"]["total_cost"] == 110
        and polymorphic_eval["fixed"]["total_cost"] == 235
        and polymorphic_eval["fixed"]["matches"] == 6
        and polymorphic_eval["causal_removal"]["losses"] == 3
        and polymorphic_eval["gates"]["minimum_two_candidate_families"]
        is False
        and polymorphic_eval["gates"]["candidate_benefit_at_least_fixed"]
        is False,
        "polymorphic prospective evaluation changed",
    )
    require(
        polymorphic_native["status"] == "POLYMORPHIC_NATIVE_DEDUP_COMPLETE"
        and polymorphic_native["summary"]["tools"] == 3
        and polymorphic_native["summary"]["validation_witnesses"] == 3
        and polymorphic_native["summary"]["compiled_both"] == 3
        and polymorphic_native["summary"][
            "normalized_inductor_duplicates"
        ]
        == 3
        and polymorphic_native["summary"]["stock_decomposition_duplicates"]
        == 3
        and polymorphic_native["summary"]["admitted"] == 0,
        "polymorphic native audit changed",
    )
    require(
        polymorphic_resource["status"]
        == "POLYMORPHIC_RESOURCE_COMPONENT_READY"
        and polymorphic_resource["P3"]["polymorphic_matrix_integrated"]
        is True
        and polymorphic_resource["P3"]["complete"] is False,
        "polymorphic resource matrix changed",
    )
    require(iteration22["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.2 inflated verdict")
    require(
        len(control_execution_prefreeze["records"]) == 6
        and control_execution_prefreeze["boundary"]["control_executed"]
        is False
        and control_execution_prefreeze["boundary"][
            "control_result_observed"
        ]
        is False
        and control_execution_prefreeze["boundary"][
            "ghost_artifacts_visible_to_control"
        ]
        is False
        and control_execution_prefreeze["boundary"][
            "missing_artifact_counts_as_reproduction"
        ]
        is False
        and control_execution_prefreeze["boundary"][
            "local_reimplementation_allowed"
        ]
        is False,
        "external-control execution boundary changed",
    )
    require(
        len(control_execution_result["records"]) == 4
        and control_execution_result["classification"]
        == "CONTROL_INFRASTRUCTURE_FAILURE"
        and control_execution_result["conformance_executed"] is False
        and control_execution_result["controls_reproduced"] == 0,
        "external-control result freeze changed",
    )
    require(
        stitch_control["status"] == "STITCH_CONTROL_INFRASTRUCTURE_FAILURE"
        and stitch_control["failure_class"] == "PINNED_WHEEL_UNAVAILABLE"
        and stitch_control["artifact_present"] is False
        and stitch_control["artifact_sha256_verified"] is False
        and stitch_control["official_backend_executed"] is False
        and stitch_control["conformance_executed"] is False
        and stitch_control["conformance_passed"] is False,
        "Stitch infrastructure result changed",
    )
    require(
        stitch_resource["status"]
        == "STITCH_CONTROL_RESOURCE_INFRASTRUCTURE_FAILURE"
        and stitch_resource["receipt_complete"] is True
        and stitch_resource["control_conformance_passed"] is False
        and stitch_resource["P1"]["controls_reproduced"] == 0
        and stitch_resource["P1"]["controls_required"] == 4
        and stitch_resource["P1"]["complete"] is False
        and stitch_resource["P3"]["stitch_control_arm_integrated"] is True
        and stitch_resource["P3"]["external_controls_integrated"] is False
        and stitch_resource["P3"]["complete"] is False,
        "Stitch control resource result changed",
    )
    require(iteration23["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.3 inflated verdict")
    require(
        len(stitch_source_result["records"]) == 5
        and stitch_source_result["classification"]
        == "SOURCE_FAITHFUL_CONTROL_WITH_BUILD_SHIMS"
        and stitch_source_result["conformance_passed"] is True
        and stitch_source_result["official_wheel_executed"] is False
        and stitch_source_result["source_faithful_controls_reproduced"] == 1,
        "Stitch source result freeze changed",
    )
    require(
        stitch_source_control["status"]
        == "STITCH_SOURCE_CONTROL_CONFORMANCE_PASS"
        and stitch_source_control["source_records_exact"] is True
        and len(stitch_source_control["source_records"]) == 28
        and stitch_source_control["upstream_algorithm_source_executed"] is True
        and stitch_source_control["official_wheel_executed"] is False
        and stitch_source_control["conformance_passed"] is True
        and all(stitch_source_control["checks"].values()),
        "Stitch source conformance changed",
    )
    require(
        stitch_source_resource["status"]
        == "STITCH_SOURCE_CONTROL_RESOURCE_PASS"
        and stitch_source_resource["receipt_complete"] is True
        and stitch_source_resource["source_conformance_passed"] is True
        and stitch_source_resource["P1"][
            "source_faithful_controls_reproduced"
        ]
        == 1
        and stitch_source_resource["P1"][
            "official_binary_controls_reproduced"
        ]
        == 0
        and stitch_source_resource["P1"]["complete"] is False,
        "Stitch source resource result changed",
    )
    require(iteration24["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.4 inflated verdict")
    require(
        len(stitch_metamorphic_prefreeze["records"]) == 7
        and stitch_metamorphic_prefreeze["boundary"][
            "metamorphic_outcome_observed"
        ]
        is False
        and stitch_metamorphic_prefreeze["boundary"][
            "expected_relation_frozen"
        ]
        is True,
        "Stitch metamorphic prefreeze changed",
    )
    require(
        len(stitch_metamorphic_result["records"]) == 5
        and stitch_metamorphic_result["classification"]
        == "PRE_FROZEN_METAMORPHIC_CONTROL_PASS"
        and stitch_metamorphic_result["metamorphic_relation_passed"] is True,
        "Stitch metamorphic result freeze changed",
    )
    require(
        stitch_metamorphic["status"] == "STITCH_METAMORPHIC_CONTROL_PASS"
        and stitch_metamorphic["upstream_source_records"] == 28
        and stitch_metamorphic["metamorphic_relation_passed"] is True
        and all(stitch_metamorphic["checks"].values()),
        "Stitch metamorphic control changed",
    )
    require(
        stitch_metamorphic_resource["status"]
        == "STITCH_METAMORPHIC_RESOURCE_PASS"
        and stitch_metamorphic_resource["receipt_complete"] is True
        and stitch_metamorphic_resource["metamorphic_relation_passed"] is True,
        "Stitch metamorphic resource result changed",
    )
    require(iteration25["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.5 inflated verdict")
    require(
        len(enumo_source_closure["records"]) == 3
        and enumo_source_closure["source_files_exact"] == 18
        and enumo_source_closure["dependencies_available"] == 10
        and enumo_source_closure["dependencies_total"] == 21
        and enumo_source_closure["control_executed"] is False,
        "Enumo source closure freeze changed",
    )
    require(
        enumo_closure["status"]
        == "ENUMO_SOURCE_READY_DEPENDENCY_CLOSURE_BLOCKED"
        and enumo_closure["source_checkout_complete"] is True
        and enumo_closure["source_files_exact"] == 18
        and enumo_closure["direct_dependencies_locally_available"] == 10
        and enumo_closure["direct_dependencies_missing"] == 11
        and enumo_closure["control_executed"] is False
        and enumo_closure["conformance_executed"] is False
        and enumo_closure["controls_reproduced"] == 1,
        "Enumo source dependency closure changed",
    )
    require(iteration26["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.6 inflated verdict")
    require(
        len(control_two_route["records"]) == 3
        and control_two_route["selected_route"] == "babble_popl23"
        and control_two_route["babble_dependencies_available"] == 13
        and control_two_route["babble_dependencies_total"] == 21
        and control_two_route["control_executed"] is False,
        "control-two route freeze changed",
    )
    require(
        route_audit["status"]
        == "CONTROL_TWO_ROUTE_SELECTED_NOT_EXECUTABLE"
        and route_audit["babble"]["resolved_commit"]
        == "09ff03fd485a3e24178c1d706a5944a230123ba1"
        and route_audit["babble"]["egg_fork_commit_from_lock"]
        == "caf623cad25cacba83193464dcf0d3dd4161ba7a"
        and route_audit["babble"]["locally_available"] == 13
        and route_audit["babble"]["missing"] == 8
        and route_audit["selection"]["route"] == "babble_popl23"
        and route_audit["selection"]["selection_is_execution"] is False
        and route_audit["selection"]["controls_reproduced"] == 1,
        "control-two acquisition route changed",
    )
    require(iteration27["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.7 inflated verdict")
    require(
        len(babble_source_result["records"]) == 5
        and babble_source_result["classification"]
        == "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION"
        and babble_source_result["structural_conformance_passed"] is True
        and babble_source_result["published_numeric_claim_exact"] is False
        and babble_source_result["full_official_cli_executed"] is False
        and babble_source_result["source_faithful_controls_reproduced"] == 2,
        "Babble source result freeze changed",
    )
    require(
        babble_source_control["status"]
        == "BABBLE_SOURCE_CONTROL_STRUCTURAL_PASS"
        and babble_source_control["source_records_exact"] is True
        and babble_source_control["source_records"] == 62
        and babble_source_control["upstream_algorithm_source_executed"] is True
        and babble_source_control["full_official_cli_executed"] is False
        and babble_source_control["structural_conformance_passed"] is True
        and babble_source_control["published_claim_audit"]["numeric_claim_exact"]
        is False
        and all(babble_source_control["checks"].values()),
        "Babble source structural conformance changed",
    )
    require(
        babble_source_resource["status"]
        == "BABBLE_SOURCE_CONTROL_RESOURCE_PASS"
        and babble_source_resource["receipt_complete"] is True
        and babble_source_resource[
            "source_structural_conformance_passed"
        ]
        is True
        and babble_source_resource["P1"][
            "source_faithful_controls_reproduced"
        ]
        == 2
        and babble_source_resource["P1"]["controls_required"] == 4
        and babble_source_resource["P1"]["complete"] is False,
        "Babble source resource result changed",
    )
    require(iteration28["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.8 inflated verdict")
    require(
        len(babble_metamorphic_prefreeze["records"]) == 9
        and babble_metamorphic_prefreeze["boundary"][
            "metamorphic_outcome_observed"
        ]
        is False
        and babble_metamorphic_prefreeze["boundary"][
            "expected_relation_frozen"
        ]
        is True
        and babble_metamorphic_prefreeze["boundary"][
            "published_fixture_values_reused"
        ]
        is False,
        "Babble metamorphic prefreeze changed",
    )
    require(
        len(babble_metamorphic_result["records"]) == 5
        and babble_metamorphic_result["classification"]
        == "PRE_FROZEN_METAMORPHIC_SOURCE_CONTROL_PASS"
        and babble_metamorphic_result["metamorphic_relation_passed"] is True,
        "Babble metamorphic result freeze changed",
    )
    require(
        babble_metamorphic["status"] == "BABBLE_METAMORPHIC_CONTROL_PASS"
        and babble_metamorphic["source_records"] == 62
        and babble_metamorphic["metamorphic_relation_passed"] is True
        and all(babble_metamorphic["checks"].values()),
        "Babble metamorphic control changed",
    )
    require(
        babble_metamorphic_resource["status"]
        == "BABBLE_METAMORPHIC_RESOURCE_PASS"
        and babble_metamorphic_resource["receipt_complete"] is True
        and babble_metamorphic_resource["metamorphic_relation_passed"] is True,
        "Babble metamorphic resource result changed",
    )
    require(iteration29["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 2.9 inflated verdict")
    require(
        len(enumo_source_result["records"]) == 5
        and enumo_source_result["classification"]
        == "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION"
        and enumo_source_result["official_boolean_conformance_passed"] is True
        and enumo_source_result["full_official_crate_executed"] is False
        and enumo_source_result["source_faithful_controls_reproduced"] == 3,
        "Enumo source result freeze changed",
    )
    require(
        enumo_source_control["status"]
        == "ENUMO_SOURCE_CONTROL_CONFORMANCE_PASS"
        and enumo_source_control["source_records_exact"] is True
        and len(enumo_source_control["source_records"]) == 49
        and enumo_source_control["upstream_algorithm_source_executed"] is True
        and enumo_source_control["full_official_crate_executed"] is False
        and enumo_source_control["observed"]["workload_counts"]
        == [93, 348, 4599]
        and enumo_source_control["observed"]["derivable_expected"] == 43
        and enumo_source_control["observed"]["expected_rules"] == 43
        and enumo_source_control["observed"]["nonderivable_expected"] == 0
        and all(enumo_source_control["checks"].values()),
        "Enumo official Boolean source conformance changed",
    )
    require(
        enumo_source_resource["status"]
        == "ENUMO_SOURCE_CONTROL_RESOURCE_PASS"
        and enumo_source_resource["receipt_complete"] is True
        and enumo_source_resource["source_conformance_passed"] is True
        and enumo_source_resource["receipt"]["observed_process_count"] == 12
        and enumo_source_resource["P1"][
            "source_faithful_controls_reproduced"
        ]
        == 3
        and enumo_source_resource["P1"]["controls_required"] == 4
        and enumo_source_resource["P1"]["complete"] is False,
        "Enumo source resource result changed",
    )
    require(iteration30["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.0 inflated verdict")
    require(
        len(enumo_metamorphic_prefreeze["records"]) == 9
        and enumo_metamorphic_prefreeze["boundary"][
            "metamorphic_outcome_observed"
        ]
        is False
        and enumo_metamorphic_prefreeze["boundary"][
            "exact_full_rule_set_relation_frozen"
        ]
        is True,
        "Enumo metamorphic prefreeze changed",
    )
    require(
        len(enumo_metamorphic_result["records"]) == 5
        and enumo_metamorphic_result["classification"]
        == "PRE_FROZEN_METAMORPHIC_CONTROL_FAIL"
        and enumo_metamorphic_result["metamorphic_relation_passed"] is False
        and enumo_metamorphic_result["execution_receipt_complete"] is True
        and enumo_metamorphic_result["baseline_rules"] == 60
        and enumo_metamorphic_result["transformed_rules"] == 67,
        "Enumo metamorphic failed-result freeze changed",
    )
    require(
        enumo_metamorphic["status"] == "ENUMO_METAMORPHIC_CONTROL_FAIL"
        and enumo_metamorphic["metamorphic_relation_passed"] is False
        and enumo_metamorphic["observed"]["workload_counts"]
        == [93, 348, 4599]
        and enumo_metamorphic["observed"]["stage_rule_counts"]
        == [26, 9, 32]
        and enumo_metamorphic["observed"]["total_rules"] == 67
        and enumo_metamorphic["checks"]["workload_counts_invariant"] is True
        and enumo_metamorphic["checks"][
            "entire_sorted_rule_set_invariant"
        ]
        is False,
        "Enumo metamorphic negative changed",
    )
    require(
        enumo_metamorphic_resource["status"]
        == "ENUMO_METAMORPHIC_RESOURCE_FAIL"
        and enumo_metamorphic_resource["receipt_complete"] is True
        and enumo_metamorphic_resource["metamorphic_relation_passed"] is False
        and enumo_metamorphic_resource["receipt"]["termination"] == "natural"
        and enumo_metamorphic_resource["receipt"]["observed_process_count"] == 12,
        "Enumo metamorphic resource evidence changed",
    )
    require(iteration31["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.1 inflated verdict")
    require(
        len(enumo_power_diagnostic["records"]) == 6
        and enumo_power_diagnostic["classification"]
        == "POST_HOC_AFTER_METAMORPHIC_FAILURE"
        and enumo_power_diagnostic["bounded_mutual_derivability"] is True
        and enumo_power_diagnostic[
            "retroactively_changes_frozen_failure"
        ]
        is False,
        "Enumo power diagnostic freeze changed",
    )
    require(
        enumo_power["status"]
        == "ENUMO_BOUNDED_PROVING_POWER_EQUIVALENT"
        and enumo_power["classification"]
        == "POST_HOC_AFTER_METAMORPHIC_FAILURE"
        and enumo_power["baseline_derives_entire_transformed_set"] is True
        and enumo_power["transformed_derives_entire_baseline_set"] is True
        and enumo_power["observed"]["baseline_derives_transformed"] == 67
        and enumo_power["observed"]["transformed_derives_baseline"] == 60,
        "Enumo bounded proving-power diagnostic changed",
    )
    require(
        enumo_power_resource["status"]
        == "ENUMO_POWER_DIAGNOSTIC_RESOURCE_PASS"
        and enumo_power_resource["receipt_complete"] is True
        and enumo_power_resource["receipt"]["termination"] == "natural"
        and enumo_power_resource["receipt"]["observed_process_count"] == 12,
        "Enumo power diagnostic resource evidence changed",
    )
    require(iteration32["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.2 inflated verdict")
    require(
        len(control_four_route["records"]) == 9
        and control_four_route["selected_route"] == "ISAMORE"
        and control_four_route["route_executable"] is False
        and control_four_route["control_executed"] is False
        and control_four_route[
            "source_faithful_controls_reproduced"
        ]
        == 3,
        "fourth-control route freeze changed",
    )
    require(
        control_four_audit["status"]
        == "CONTROL_FOUR_ROUTE_SELECTED_NOT_EXECUTABLE"
        and control_four_audit["source_records_exact"] is True
        and len(control_four_audit["source_records"]) == 6
        and control_four_audit["route"]["system"] == "ISAMORE"
        and control_four_audit["route"][
            "independent_top_level_implementation"
        ]
        is True
        and control_four_audit["route"][
            "reuses_babble_and_enumo_as_subsystems"
        ]
        is True
        and control_four_audit["closure"]["manifest_dependencies"] == 35
        and control_four_audit["closure"]["registry_dependencies"] == 30
        and control_four_audit["closure"][
            "registry_dependencies_locally_available"
        ]
        == 14
        and len(control_four_audit["closure"]["missing_submodules"]) == 4
        and len(control_four_audit["closure"]["missing_workspace_paths"]) == 4
        and control_four_audit["closure"][
            "required_rust_toolchain_present"
        ]
        is False
        and control_four_audit["closure"]["clang_18_or_newer_present"] is True
        and control_four_audit["closure"]["jlm_opt_present"] is False
        and control_four_audit["closure"][
            "published_template_inputs_present"
        ]
        is False
        and control_four_audit["route_executable"] is False
        and control_four_audit["control_executed"] is False
        and control_four_audit["controls_reproduced"] == 3,
        "fourth-control acquisition audit changed",
    )
    require(iteration33["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.3 inflated verdict")
    require(
        len(isamore_reduced_route["records"]) == 5
        and isamore_reduced_route["classification"]
        == "EVIDENCE_BACKED_ROUTE_REJECTION"
        and isamore_reduced_route["reduced_route_faithful"] is False
        and isamore_reduced_route["control_executed"] is False
        and isamore_reduced_route[
            "source_faithful_controls_reproduced"
        ]
        == 3,
        "ISAMORE reduced-route freeze changed",
    )
    require(
        isamore_reduced_audit["status"]
        == "ISAMORE_REDUCED_ROUTE_REJECTED"
        and isamore_reduced_audit["core_blob_identities_observed"] == 5
        and isamore_reduced_audit["core_files_materialized_locally"] is False
        and isamore_reduced_audit[
            "recursive_submodule_identities_observed"
        ]
        is False
        and isamore_reduced_audit["runner_observations"][
            "top_level_run_calls_prune_then_lib_select"
        ]
        is True
        and isamore_reduced_audit["runner_observations"][
            "area_cycle_frontier_computed"
        ]
        is True
        and isamore_reduced_audit["runner_observations"][
            "hardware_selection_separable_from_library_learning"
        ]
        is False
        and isamore_reduced_audit["reduced_route_faithful"] is False
        and isamore_reduced_audit["control_executed"] is False
        and isamore_reduced_audit["controls_reproduced"] == 3,
        "ISAMORE reduced-route rejection changed",
    )
    require(iteration34["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.4 inflated verdict")
    require(
        len(diversity_calibration["records"]) == 6
        and diversity_calibration["classification"]
        == "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        and diversity_calibration["graphs"] == 19
        and diversity_calibration["patterns_enumerated"] == 149
        and diversity_calibration["selected_patterns"] == 11
        and diversity_calibration["fixed_target_sequence_duplicates"] == 5
        and diversity_calibration["novel_target_sequences"] == 6
        and diversity_calibration["prospective_claim_allowed"] is False,
        "diversity calibration freeze changed",
    )
    require(
        diversity_audit["status"]
        == "DIVERSITY_CALIBRATION_AUDIT_COMPLETE"
        and diversity_audit["classification"]
        == "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        and len(diversity_audit["graph_rows"]) == 19
        and len(diversity_audit["unsupported"]) == 1
        and diversity_audit["unsupported"][0]["family"]
        == "siamese_image_comparison"
        and diversity_audit["candidate_patterns_enumerated"] == 149
        and diversity_audit["selection"]["selected_patterns"] == 11
        and diversity_audit["selection"][
            "fixed_target_sequence_duplicates"
        ]
        == 5
        and diversity_audit["selection"]["novel_target_sequences"] == 6
        and any(
            row["target_sequence"]
            == ["aten.mm.default", "aten.add.Tensor"]
            and row["family_count"] == 3
            and row["suite_count"] == 3
            and row["repository_count"] == 2
            for row in diversity_audit["novel"]
        )
        and diversity_audit["autonomy_boundary"]["llm_calls"] == 0
        and diversity_audit["autonomy_boundary"][
            "prospective_claim_allowed"
        ]
        is False,
        "diversity calibration result changed",
    )
    require(
        diversity_resource["status"]
        == "DIVERSITY_CALIBRATION_RESOURCE_PASS"
        and diversity_resource["receipt_complete"] is True
        and diversity_resource["calibration_completed"] is True
        and diversity_resource["prospective_claim_allowed"] is False
        and diversity_resource["receipt"]["termination"] == "natural",
        "diversity calibration resource evidence changed",
    )
    require(iteration35["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.5 inflated verdict")
    require(
        external_validation_v5["classification"]
        == "PROSPECTIVE_SOURCE_INTAKE_FROZEN_PRE_EXECUTION"
        and external_validation_v5["source_count"] == 4
        and external_validation_v5["repository_count"] == 4
        and external_validation_v5["semantic_domain_count"] == 4
        and external_validation_v5["transformer_or_attention_count"] == 0
        and external_validation_v5[
            "candidate_or_fixed_execution_observed"
        ]
        is False
        and external_validation_v5["validation_runtime_executed"] is False,
        "external validation-v5 source boundary changed",
    )
    require(
        diversity_candidate["classification"]
        == "PROSPECTIVE_PROTOCOL_FROZEN_PRE_OUTCOME"
        and diversity_candidate["tools_forged"] == 3
        and diversity_candidate["independent_replays"] == 21
        and diversity_candidate["native_runtime_inventions_admitted"] == 0
        and diversity_candidate["prospective_outcomes_observed"] is False
        and diversity_candidate["post_freeze_intervention_allowed"] is False,
        "diversity candidate protocol freeze changed",
    )
    require(
        diversity_forge["status"] == "DIVERSITY_TOOL_FORGE_READY"
        and diversity_forge["classification"]
        == "CALIBRATION_ONLY_CANDIDATE_CONSTRUCTION"
        and diversity_forge["source_motifs"] == 6
        and diversity_forge["represented_source_motifs"] == 3
        and diversity_forge["executable_body_groups"] == 12
        and diversity_forge["tools_forged"] == 3
        and diversity_forge["autonomy_boundary"]["llm_calls"] == 0
        and diversity_forge["autonomy_boundary"]["supplied_tool_forms"] == 0
        and diversity_forge["access_audit"]["forbidden_open_count"] == 0,
        "diversity forge evidence changed",
    )
    require(
        diversity_conformance["status"]
        == "DIVERSITY_TOOL_INDEPENDENT_CONFORMANCE_PASS"
        and diversity_conformance["classification"]
        == "CALIBRATION_ONLY_INDEPENDENT_CONFORMANCE"
        and diversity_conformance["tools"] == 3
        and diversity_conformance["graphs"] == 19
        and diversity_conformance["successful_replays"] == 21
        and len(diversity_conformance["hostile_rejections"]) == 5
        and all(diversity_conformance["gates"].values())
        and diversity_conformance[
            "validation_source_or_runtime_accessed"
        ]
        is False,
        "independent diversity conformance changed",
    )
    require(
        diversity_native["status"] == "DIVERSITY_NATIVE_DEDUP_COMPLETE"
        and diversity_native["summary"]["tools"] == 3
        and diversity_native["summary"]["stock_decomposition_duplicates"]
        == 3
        and diversity_native["summary"]["compiled_both"] == 3
        and diversity_native["summary"]["normalized_inductor_duplicates"]
        == 3
        and diversity_native["summary"]["runtime_inventions_admitted"] == 0
        and diversity_native["summary"][
            "semantic_search_candidates_retained"
        ]
        == 3,
        "diversity native dedup changed",
    )
    require(
        diversity_candidate_resource["status"]
        == "DIVERSITY_RESOURCE_COMPONENT_READY"
        and all(diversity_candidate_resource["gates"].values())
        and len(diversity_candidate_resource["arms"]) == 3
        and diversity_candidate_resource[
            "validation_source_or_runtime_accessed"
        ]
        is False,
        "diversity candidate resource matrix changed",
    )
    require(
        diversity_result["classification"] == "PROSPECTIVE_VALID_NEGATIVE"
        and diversity_result["exported_graphs"] == 4
        and diversity_result["candidate_matched_tools"] == 2
        and diversity_result["candidate_matched_families"] == 3
        and diversity_result["candidate_unique_node_benefit"] == 11
        and diversity_result["fixed_unique_node_benefit"] == 13
        and diversity_result["candidate_total_cost"] == 294
        and diversity_result["fixed_total_cost"] == 244
        and diversity_result["candidate_only_families"] == 0
        and diversity_result["posthoc_reclassification_allowed"] is False,
        "prospective diversity result freeze changed",
    )
    require(
        diversity_trial["status"] == "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE"
        and diversity_trial["sources"] == 4
        and diversity_trial["exported_graphs"] == 4
        and not diversity_trial["graph_failures"]
        and diversity_trial["candidate"]["tools"] == 3
        and diversity_trial["candidate"]["matched_tools"] == 2
        and diversity_trial["candidate"]["matched_families"] == 3
        and diversity_trial["candidate"]["matched_repositories"] == 3
        and diversity_trial["candidate"]["matched_semantic_domains"] == 3
        and diversity_trial["candidate"]["unique_node_benefit"] == 11
        and diversity_trial["candidate"]["total_cost"] == 294
        and diversity_trial["fixed"]["unique_node_benefit"] == 13
        and diversity_trial["fixed"]["total_cost"] == 244
        and len(diversity_trial["candidate_only_families"]) == 0
        and diversity_trial["gates"]["all_four_graphs_exported_and_executed"]
        is True
        and diversity_trial["gates"]["all_candidate_replays_exact"] is True
        and diversity_trial["gates"][
            "candidate_unique_benefit_at_least_fixed"
        ]
        is False
        and diversity_trial["gates"]["candidate_total_cost_below_fixed"]
        is False
        and diversity_trial["gates"]["cheaper_or_newly_reachable_family"]
        is False,
        "prospective diversity trial changed",
    )
    require(
        diversity_trial_resource["status"]
        == "PROSPECTIVE_DIVERSITY_RESOURCE_PASS"
        and diversity_trial_resource["receipt_complete"] is True
        and diversity_trial_resource["result_complete"] is True
        and diversity_trial_resource["receipt"]["termination"] == "natural"
        and diversity_trial_resource["receipt"]["process_group_reaped"]
        is True,
        "prospective diversity resource evidence changed",
    )
    require(iteration36["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.6 inflated verdict")
    require(
        diversity_failure_calibration["classification"]
        == "POST_PROSPECTIVE_CALIBRATION_ONLY"
        and diversity_failure_calibration["failed_gates"] == 4
        and diversity_failure_calibration["candidate_coverage_deficit"] == 2
        and diversity_failure_calibration[
            "discarded_machine_rediscovered_fixed_sequences"
        ]
        == 5
        and diversity_failure_calibration[
            "equal_cohort_efficiency_break_even"
        ]
        == 2
        and diversity_failure_calibration["prospective_claim_allowed"]
        is False,
        "diversity failure-calibration freeze changed",
    )
    require(
        diversity_failure["status"]
        == "DIVERSITY_FAILURE_MECHANISM_AUDIT_COMPLETE"
        and diversity_failure["classification"]
        == "POST_PROSPECTIVE_CALIBRATION_ONLY"
        and len(diversity_failure["failed_gates"]) == 4
        and diversity_failure["mechanisms"]["coverage_deficit"]["deficit"]
        == 2
        and diversity_failure["mechanisms"][
            "novelty_only_portfolio_constraint"
        ]["machine_rediscovered_fixed_sequences_discarded"]
        == 5
        and diversity_failure["mechanisms"]["upfront_search_amortization"][
            "repeated_equal_cohort_efficiency_break_even"
        ]
        == 2
        and diversity_failure["prospective_claim_allowed"] is False,
        "diversity failure mechanism audit changed",
    )
    require(
        diversity_failure_resource["status"]
        == "DIVERSITY_FAILURE_RESOURCE_PASS"
        and diversity_failure_resource["receipt_complete"] is True
        and diversity_failure_resource["prospective_claim_allowed"] is False
        and diversity_failure_resource["receipt"]["termination"] == "natural",
        "diversity failure resource audit changed",
    )
    require(iteration37["verdict"] == "FOUNDRY_V6_NOT_READY", "iteration 3.7 inflated verdict")
    require(
        len(external_validation_v6["records"]) == 10
        and external_validation_v6["source_count"] == 4
        and external_validation_v6["repository_count"] == 4
        and external_validation_v6["semantic_domain_count"] == 4
        and external_validation_v6["transformer_or_attention_count"] == 0
        and external_validation_v6["validation_graphs_exported_or_inspected"]
        is False
        and external_validation_v6["validation_runtime_executed"] is False,
        "validation-v6 source boundary changed",
    )
    require(
        pareto_calibration["status"] == "PARETO_MOTIF_POOL_READY"
        and pareto_calibration["graphs"] == 23
        and pareto_calibration["paths_enumerated"] == 581
        and pareto_calibration["exact_body_groups"] == 339
        and pareto_calibration["eligible_tools"] == 10
        and pareto_calibration["access_audit"]["forbidden_open_count"] == 0,
        "Pareto calibration evidence changed",
    )
    require(
        pareto_optimizer["status"] == "PARETO_PORTFOLIO_SELECTED"
        and pareto_optimizer["candidate_subsets"] == 1023
        and pareto_optimizer["selected"]["tools"] == 4
        and pareto_optimizer["selected"]["unique_nodes"] == 53
        and pareto_optimizer["selected"]["total_cost"] == 2234
        and pareto_optimizer["fixed"]["unique_nodes"] == 51
        and pareto_optimizer["fixed"]["total_cost"] == 2616
        and pareto_optimizer["ablations"]["novelty_only"]["unique_nodes"]
        == 50
        and pareto_optimizer["ablations"]["all_motif"]["unique_nodes"] == 58
        and pareto_optimizer["access_audit"]["forbidden_open_count"] == 0,
        "Pareto optimizer evidence changed",
    )
    require(
        pareto_conformance["status"]
        == "PARETO_INDEPENDENT_CONFORMANCE_PASS"
        and pareto_conformance["successful_replays"] == 34
        and len(pareto_conformance["hostile_rejections"]) == 7,
        "Pareto independent conformance changed",
    )
    require(
        pareto_native["status"] == "PARETO_NATIVE_DEDUP_COMPLETE"
        and pareto_native["summary"]["tools"] == 4
        and pareto_native["summary"]["compiled_both"] == 4
        and pareto_native["summary"]["normalized_inductor_duplicates"] == 4
        and pareto_native["summary"]["stock_decomposition_duplicates"] == 4
        and pareto_native["summary"]["runtime_inventions_admitted"] == 0,
        "Pareto native classification changed",
    )
    require(
        pareto_resource["status"] == "PARETO_RESOURCE_COMPONENT_READY"
        and all(pareto_resource["gates"].values())
        and pareto_resource["validation_v6_accessed"] is False,
        "Pareto resource matrix changed",
    )
    require(
        len(pareto_candidate["records"]) == 22
        and pareto_candidate["heldout_execution_observed"] is False
        and pareto_candidate["runtime_inventions_admitted"] == 0,
        "Pareto candidate freeze changed",
    )
    require(
        pareto_authorization["status"]
        == "PARETO_PROSPECTIVE_NOT_AUTHORIZED"
        and sum(pareto_authorization["prerequisites"].values()) == 3
        and len(
            pareto_authorization["production_integrated_required_arms"]
        )
        == 2
        and sum(
            value is True
            for value in pareto_authorization["stop_conditions"].values()
        )
        == 2
        and pareto_authorization["prospective_trial_authorized"] is False
        and pareto_authorization["heldout_import_or_execution_observed"]
        is False,
        "Pareto authorization result changed",
    )
    require(
        authorization_access["status"]
        == "AUTHORIZATION_ACCESS_RESOURCE_PASS"
        and authorization_access["heldout_manifest_accessed"] is True
        and authorization_access[
            "heldout_source_runtime_or_graph_accessed"
        ]
        is False
        and authorization_access["prospective_trial_authorized"] is False
        and authorization_access["receipt"]["termination"] == "natural",
        "authorization access/resource audit changed",
    )
    require(
        len(pareto_authorization_result["records"]) == 6
        and pareto_authorization_result["prospective_trial_authorized"]
        is False
        and pareto_authorization_result[
            "heldout_source_runtime_or_graph_accessed"
        ]
        is False,
        "Pareto authorization freeze changed",
    )
    require(
        eggmind_source_route["status"]
        == "EGGMIND_UPSTREAM_SOURCE_NOT_DISCOVERED"
        and eggmind_source_route["search_routes"] == 6
        and eggmind_source_route["official_repository_matches"] == 0
        and eggmind_source_route["P1"]["complete"] is False,
        "EggMind source-route evidence changed",
    )
    require(
        eggmind_boundary["status"]
        == "EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_PASS"
        and eggmind_boundary["schedule_counts"]
        == {"actions": 61, "phases": 41, "simplifications": 20}
        and len(eggmind_boundary["hostile_rejections"]) == 7
        and all(eggmind_boundary["checks"].values())
        and eggmind_boundary["P1"]["complete"] is False,
        "EggMind adapted-boundary evidence changed",
    )
    require(
        per_instance_controls["status"]
        == "PER_INSTANCE_CONTROL_KERNELS_CONFORMANCE_PASS"
        and all(per_instance_controls["checks"].values())
        and per_instance_controls["A3"]["summary"][
            "search_construction_units"
        ]
        == per_instance_controls["A9"]["summary"][
            "search_construction_units"
        ]
        == 969
        and per_instance_controls["A3"]["summary"]["exact_body_groups"]
        == per_instance_controls["A9"]["summary"]["exact_body_groups"]
        == 388
        and per_instance_controls["A3"]["summary"]["unique_nodes_covered"]
        == 126
        and per_instance_controls["A9"]["summary"]["unique_nodes_covered"]
        == 226
        and per_instance_controls["production_boundary"][
            "prospective_arm_complete"
        ]
        is False,
        "A3/A9 control conformance changed",
    )
    require(
        per_instance_resource["status"]
        == "PER_INSTANCE_CONTROL_RESOURCE_COMPONENT_READY"
        and all(per_instance_resource["checks"].values())
        and per_instance_resource["P3"]["complete"] is False
        and per_instance_resource["validation_v6_accessed"] is False,
        "A3/A9 resource evidence changed",
    )
    require(
        len(pareto_remediation["records"]) == 14
        and pareto_remediation["A3_calibration_conformance"] is True
        and pareto_remediation["A8_full_conformance"] is False
        and pareto_remediation["A9_calibration_conformance"] is True
        and pareto_remediation["prospective_trial_authorized"] is False
        and pareto_remediation[
            "heldout_source_runtime_or_graph_accessed"
        ]
        is False,
        "Pareto remediation freeze changed",
    )
    require(
        iteration38["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration38["progress"]["full_A8_conformance"] is False,
        "iteration 3.8 inflated verdict",
    )
    require(
        iteration39["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration39["authorization"]["prerequisites_passed"] == 3
        and iteration39["authorization"][
            "required_arms_production_integrated"
        ]
        == 2
        and iteration39["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 3.9 inflated verdict",
    )
    require(
        external_invocation_trace["status"]
        == "EXTERNAL_INVOCATION_HORIZON_COMPONENT_READY"
        and all(external_invocation_trace["checks"].values())
        and external_invocation_trace["trace"]["rows"] == 26823
        and external_invocation_trace["trace"]["models"] == 86
        and external_invocation_trace["N_star_external_reference"] == 3
        and external_invocation_trace["P2"]["complete"] is False
        and external_invocation_trace["validation_v6_accessed"] is False,
        "external invocation trace evidence changed",
    )
    require(
        external_trace_replay["status"]
        == "EXTERNAL_TRACE_INDEPENDENT_REPLAY_PASS"
        and all(external_trace_replay["checks"].values())
        and external_trace_replay["exact_relations_passed"]
        == external_trace_replay["exact_relations_total"]
        == 12
        and external_trace_replay["N_star_external_reference"] == 3
        and external_trace_replay["scientific_boundary"]["P2_complete"]
        is False,
        "independent external trace replay changed",
    )
    require(
        external_horizon_sensitivity["status"]
        == "CALIBRATION_HORIZON_SENSITIVITY_PASS"
        and all(external_horizon_sensitivity["checks"].values())
        and external_horizon_sensitivity["primary"]["N"] == 3
        and external_horizon_sensitivity["primary"]["candidate_cost"]
        == 4862
        and external_horizon_sensitivity["primary"]["fixed_cost"] == 7848
        and external_horizon_sensitivity["P2"]["complete"] is False
        and external_horizon_sensitivity["validation_v6_accessed"] is False,
        "external horizon sensitivity changed",
    )
    require(
        len(pareto_remediation_v2["records"]) == 15
        and pareto_remediation_v2["phases"] == [74, 75, 76]
        and pareto_remediation_v2["external_N_star_reference"] == 3
        and pareto_remediation_v2["P2_complete"] is False
        and pareto_remediation_v2["prospective_trial_authorized"] is False
        and pareto_remediation_v2[
            "heldout_source_runtime_or_graph_accessed"
        ]
        is False,
        "Pareto remediation-v2 freeze changed",
    )
    require(
        iteration40["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration40["progress"]["external_N_star_reference"] == 3
        and iteration40["progress"][
            "invocation_horizon_stop_condition_cleared"
        ]
        is True
        and iteration40["authorization"]["prerequisites_passed"] == 3
        and iteration40["authorization"]["active_stop_conditions"] == 1
        and iteration40["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.0 inflated verdict",
    )
    require(
        local_trace_provenance["status"]
        == "LOCAL_TRACE_BYTES_AUTHENTICATED"
        and all(local_trace_provenance["checks"].values())
        and len(local_trace_provenance["records"]) == 3
        and local_trace_provenance["records"][2]["bytes"] == 2012418
        and local_trace_provenance["records"][2]["computed_git_blob_sha1"]
        == "db8d3cfaea62e7086aff40e98ab6446619d9e5ce"
        and local_trace_provenance["P2"][
            "trace_source_bytes_locally_frozen"
        ]
        is True
        and local_trace_provenance["P2"]["complete"] is False,
        "local trace provenance changed",
    )
    require(
        offline_trace_replay["status"] == "OFFLINE_TRACE_REPLAY_PASS"
        and all(offline_trace_replay["checks"].values())
        and offline_trace_replay["stdlib_parser"]
        == offline_trace_replay["independent_byte_parser"]
        == offline_trace_replay["connector_receipt"]
        and offline_trace_replay["stdlib_parser"]["data_rows"] == 26823
        and offline_trace_replay["stdlib_parser"][
            "nonempty_model_identities"
        ]
        == 86
        and offline_trace_replay["P2"]["complete"] is False,
        "offline trace replay changed",
    )
    require(
        offline_trace_resource["status"]
        == "OFFLINE_TRACE_PIPELINE_RESOURCE_PASS"
        and all(offline_trace_resource["checks"].values())
        and offline_trace_resource["P3"]["complete"] is False
        and offline_trace_resource["validation_v6_accessed"] is False,
        "offline trace resource evidence changed",
    )
    require(
        horizon_unit_mapping["status"]
        == "HORIZON_UNIT_MAPPING_REJECTED_CURRENT_PROTOCOL"
        and all(horizon_unit_mapping["checks"].values())
        and horizon_unit_mapping["mappings"][
            "M1_request_q25_to_artifact_N"
        ]["decision"]
        == "REJECT_UNIT_MISMATCH"
        and horizon_unit_mapping["P2"]["execution_multiplicity_K_star"]
        == 3
        and horizon_unit_mapping["P2"][
            "artifact_stream_N_star_justified"
        ]
        is False,
        "horizon unit rejection changed",
    )
    require(
        horizon_clarification["status"]
        == "HORIZON_CLARIFICATION_CONFORMANCE_PASS"
        and all(horizon_clarification["independent"]["checks"].values())
        and horizon_clarification["independent"]["checks_passed"]
        == horizon_clarification["independent"]["checks_total"]
        == 18
        and horizon_clarification["P2"]["primary_coordinates"]
        == {
            "artifacts": 4,
            "execution_events": 12,
            "invocations_per_artifact": 3,
            "pairing_unit": "artifact",
        }
        and horizon_clarification["P2"]["complete"] is True
        and horizon_clarification[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "horizon clarification conformance changed",
    )
    require(
        horizon_protocol_resource["status"]
        == "HORIZON_PROTOCOL_RESOURCE_PASS"
        and all(horizon_protocol_resource["checks"].values())
        and horizon_protocol_resource["P3"]["complete"] is False
        and horizon_protocol_resource[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "horizon protocol resource evidence changed",
    )
    require(
        len(pareto_remediation_v3["records"]) == 22
        and pareto_remediation_v3["phases"] == [77, 78, 79, 80, 81, 82]
        and pareto_remediation_v3["artifact_coordinate"] == 4
        and pareto_remediation_v3["invocations_per_artifact"] == 3
        and pareto_remediation_v3["P2_complete"] is True
        and pareto_remediation_v3["P3_complete"] is False
        and pareto_remediation_v3["current_prerequisites_passed"] == 4
        and pareto_remediation_v3["prospective_trial_authorized"] is False,
        "Pareto remediation-v3 freeze changed",
    )
    require(
        iteration41["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration41["prerequisites"][
            "P2_independent_corpus_and_invocation_trace"
        ]
        is True
        and iteration41["authorization"]["prerequisites_passed"] == 4
        and iteration41["authorization"]["required_arms_production_integrated"]
        == 2
        and iteration41["authorization"]["active_stop_conditions"] == 1
        and iteration41["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.1 inflated verdict",
    )
    require(
        arm_adapter_conformance["status"]
        == "ARM_ADAPTER_CONTRACT_CONFORMANCE_PASS"
        and all(arm_adapter_conformance["checks"].values())
        and len(arm_adapter_conformance["hostile_rejections"]) == 9
        and all(
            row["rejected_twice"]
            for row in arm_adapter_conformance["hostile_rejections"]
        )
        and arm_adapter_conformance["integration"]["required_arms_named"]
        == 10
        and arm_adapter_conformance["integration"][
            "production_integrated_arms"
        ]
        == 2
        and arm_adapter_conformance["P3"]["complete"] is False
        and arm_adapter_conformance["validation_v6_accessed"] is False,
        "arm adapter conformance changed",
    )
    require(
        arm_adapter_resource["status"]
        == "ARM_ADAPTER_CONTRACT_RESOURCE_PASS"
        and all(arm_adapter_resource["checks"].values())
        and arm_adapter_resource["P3"][
            "adapter_contract_conformance_metered"
        ]
        is True
        and arm_adapter_resource["P3"]["complete"] is False
        and arm_adapter_resource["validation_v6_accessed"] is False,
        "arm adapter resource evidence changed",
    )
    require(
        len(pareto_remediation_v4["records"]) == 9
        and pareto_remediation_v4["phases"] == [83, 84]
        and pareto_remediation_v4["required_arms_named"] == 10
        and pareto_remediation_v4["production_integrated_arms"] == 2
        and pareto_remediation_v4[
            "hostile_mutations_rejected_twice"
        ]
        == 9
        and pareto_remediation_v4["P3_complete"] is False
        and pareto_remediation_v4["prospective_trial_authorized"] is False,
        "Pareto remediation-v4 freeze changed",
    )
    require(
        iteration42["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration42["progress"]["arm_adapter_contract_ready"] is True
        and iteration42["progress"]["required_arms_named"] == 10
        and iteration42["progress"]["production_integrated_arms"] == 2
        and iteration42["progress"]["P3_complete"] is False
        and iteration42["authorization"]["prerequisites_passed"] == 4
        and iteration42["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.2 inflated verdict",
    )
    require(
        state_reset_adapter["status"]
        == "STATE_RESET_ADAPTER_BOUNDED_CONFORMANCE_PASS"
        and all(state_reset_adapter["checks"].values())
        and len(state_reset_adapter["hostile_rejections"]) == 9
        and all(
            row["rejected_twice"]
            for row in state_reset_adapter["hostile_rejections"]
        )
        and state_reset_adapter["arms"]["A3"]["motifs"]
        == {
            "exact_typed_body_groups": 8,
            "paths_enumerated": 13,
            "search_construction_units": 21,
            "tools_selected": 3,
            "unique_nodes_covered": 6,
        }
        and state_reset_adapter["arms"]["A9"]["motifs"]
        == {
            "exact_typed_body_groups": 8,
            "paths_enumerated": 13,
            "search_construction_units": 21,
            "tools_selected": 2,
            "unique_nodes_covered": 8,
        }
        and state_reset_adapter["integration"][
            "production_integrated_arms"
        ]
        == 2
        and state_reset_adapter["P3"]["complete"] is False
        and state_reset_adapter["validation_v6_accessed"] is False,
        "bounded A3/A9 adapter conformance changed",
    )
    require(
        state_reset_resource["status"]
        == "STATE_RESET_ADAPTER_RESOURCE_COMPONENT_PASS"
        and all(state_reset_resource["checks"].values())
        and sorted(state_reset_resource["arms"]) == ["A3", "A9"]
        and state_reset_resource["P3"][
            "A3_bounded_adapter_process_tree_metered"
        ]
        is True
        and state_reset_resource["P3"][
            "A9_bounded_adapter_process_tree_metered"
        ]
        is True
        and state_reset_resource["P3"]["complete"] is False
        and state_reset_resource["production_integrated_arms"] == 2
        and state_reset_resource["validation_v6_accessed"] is False,
        "bounded A3/A9 adapter resource evidence changed",
    )
    require(
        len(pareto_remediation_v5["records"]) == 13
        and pareto_remediation_v5["phases"] == [85, 86]
        and pareto_remediation_v5["A3_bounded_adapter_ready"] is True
        and pareto_remediation_v5["A9_bounded_adapter_ready"] is True
        and pareto_remediation_v5["bounded_operator_count"] == 3
        and pareto_remediation_v5["production_integrated_arms"] == 2
        and pareto_remediation_v5["P3_complete"] is False
        and pareto_remediation_v5["prospective_trial_authorized"] is False,
        "Pareto remediation-v5 freeze changed",
    )
    require(
        iteration43["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration43["progress"][
            "A3_bounded_typed_dag_adapter_ready"
        ]
        is True
        and iteration43["progress"][
            "A9_bounded_typed_dag_adapter_ready"
        ]
        is True
        and iteration43["progress"]["bounded_operator_count"] == 3
        and iteration43["progress"]["production_integrated_arms"] == 2
        and iteration43["progress"]["P3_complete"] is False
        and iteration43["authorization"]["prerequisites_passed"] == 4
        and iteration43["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.3 inflated verdict",
    )
    require(
        operator_vocab["status"]
        == "MANUAL_INTERPRETER_ROUTE_REJECTED_INCOMPLETE_SURFACE"
        and all(operator_vocab["checks"].values())
        and operator_vocab["summary"]["graphs"] == 23
        and operator_vocab["summary"]["unique_operators"] == 41
        and operator_vocab["summary"]["call_function_invocations"] == 337
        and operator_vocab["summary"]["bounded_unique_operators"] == 3
        and operator_vocab["summary"]["bounded_invocations"] == 53
        and operator_vocab["decision"][
            "manual_typed_dag_interpreter_production_ready"
        ]
        is False
        and operator_vocab["decision"]["required_route"]
        == "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT"
        and operator_vocab["P3"]["complete"] is False
        and operator_vocab["validation_v6_accessed"] is False,
        "operator vocabulary route evidence changed",
    )
    require(
        operator_vocab_resource["status"]
        == "OPERATOR_VOCAB_ROUTE_RESOURCE_PASS"
        and all(operator_vocab_resource["checks"].values())
        and operator_vocab_resource["P3"][
            "operator_route_audit_process_tree_metered"
        ]
        is True
        and operator_vocab_resource["P3"]["complete"] is False
        and operator_vocab_resource["production_integrated_arms"] == 2
        and operator_vocab_resource["validation_v6_accessed"] is False,
        "operator vocabulary resource evidence changed",
    )
    require(
        len(pareto_remediation_v6["records"]) == 7
        and pareto_remediation_v6["phases"] == [87, 88]
        and pareto_remediation_v6["calibration_graphs"] == 23
        and pareto_remediation_v6["unique_operators"] == 41
        and pareto_remediation_v6["bounded_operator_count"] == 3
        and pareto_remediation_v6["required_runtime_route"]
        == "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT"
        and pareto_remediation_v6["production_integrated_arms"] == 2
        and pareto_remediation_v6["P3_complete"] is False
        and pareto_remediation_v6["prospective_trial_authorized"] is False,
        "Pareto remediation-v6 freeze changed",
    )
    require(
        iteration44["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration44["progress"]["calibration_unique_operators"] == 41
        and iteration44["progress"]["bounded_unique_operators"] == 3
        and iteration44["progress"][
            "manual_interpreter_production_ready"
        ]
        is False
        and iteration44["progress"]["required_runtime_route"]
        == "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT"
        and iteration44["progress"]["P3_complete"] is False
        and iteration44["authorization"]["prerequisites_passed"] == 4
        and iteration44["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.4 inflated verdict",
    )
    require(
        framework_mount["status"]
        == "FRAMEWORK_RUNTIME_MOUNT_COMPONENT_PASS"
        and all(framework_mount["checks"].values())
        and framework_mount["integration"]["calibration_graphs_mounted"]
        == 23
        and framework_mount["integration"][
            "calibration_operator_targets_executed"
        ]
        == 41
        and framework_mount["arms"]["A3"]["summary"][
            "framework_executions"
        ]
        == framework_mount["arms"]["A9"]["summary"][
            "framework_executions"
        ]
        == 69
        and framework_mount["arms"]["A3"]["summary"]["max_abs_error"]
        == framework_mount["arms"]["A9"]["summary"]["max_abs_error"]
        == 0.0
        and framework_mount["integration"]["production_integrated_arms"]
        == 2
        and framework_mount["P3"]["complete"] is False
        and framework_mount["validation_v6_accessed"] is False,
        "framework runtime mount evidence changed",
    )
    require(
        framework_mount_resource["status"]
        == "FRAMEWORK_RUNTIME_MOUNT_RESOURCE_COMPONENT_PASS"
        and all(framework_mount_resource["checks"].values())
        and framework_mount_resource["P3"][
            "A3_A9_complete_mount_process_trees_metered"
        ]
        is True
        and framework_mount_resource["P3"]["complete"] is False
        and framework_mount_resource["production_integrated_arms"] == 2
        and framework_mount_resource["validation_v6_accessed"] is False,
        "framework mount resource evidence changed",
    )
    require(
        len(pareto_remediation_v7["records"]) == 9
        and pareto_remediation_v7["phases"] == [89, 90]
        and pareto_remediation_v7["calibration_graphs"] == 23
        and pareto_remediation_v7["unique_operators_executed"] == 41
        and pareto_remediation_v7["framework_executions_per_arm"] == 69
        and pareto_remediation_v7[
            "A3_A9_runtime_mount_component_ready"
        ]
        is True
        and pareto_remediation_v7["production_integrated_arms"] == 2
        and pareto_remediation_v7["P3_complete"] is False
        and pareto_remediation_v7["prospective_trial_authorized"] is False,
        "Pareto remediation-v7 freeze changed",
    )
    require(
        iteration45["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration45["progress"][
            "framework_runtime_mount_component_ready"
        ]
        is True
        and iteration45["progress"]["calibration_graphs_mounted"] == 23
        and iteration45["progress"][
            "calibration_unique_operators_executed"
        ]
        == 41
        and iteration45["progress"][
            "A3_A9_complete_mount_process_trees_metered"
        ]
        is True
        and iteration45["progress"]["P3_complete"] is False
        and iteration45["authorization"]["prerequisites_passed"] == 4
        and iteration45["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.5 inflated verdict",
    )
    require(
        shared_resource_batch["status"]
        == "SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(shared_resource_batch["checks"].values())
        and len(shared_resource_batch["hostile_rejections"]) == 9
        and all(
            row["rejected_twice"]
            for row in shared_resource_batch["hostile_rejections"]
        )
        and shared_resource_batch["integration"][
            "production_integrated_arms"
        ]
        == 4
        and shared_resource_batch["P3"][
            "A3_A9_complete_contract_batches_ready"
        ]
        is True
        and shared_resource_batch["P3"]["complete"] is False
        and shared_resource_batch["validation_v6_accessed"] is False,
        "shared resource batch evidence changed",
    )
    require(
        shared_resource_batch_resource["status"]
        == "SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(shared_resource_batch_resource["checks"].values())
        and shared_resource_batch_resource["integration"][
            "production_integrated_arms"
        ]
        == 4
        and shared_resource_batch_resource["P3"][
            "A3_A9_complete_contract_batches_ready"
        ]
        is True
        and shared_resource_batch_resource["P3"]["complete"] is False
        and shared_resource_batch_resource["validation_v6_accessed"]
        is False,
        "shared resource batch resource evidence changed",
    )
    require(
        len(pareto_remediation_v8["records"]) == 9
        and pareto_remediation_v8["phases"] == [91, 92]
        and pareto_remediation_v8["base_contract_pairs_accepted"] == 46
        and pareto_remediation_v8[
            "shared_resource_receipts_charged"
        ]
        == 2
        and pareto_remediation_v8[
            "hostile_batches_rejected_twice"
        ]
        == 9
        and pareto_remediation_v8[
            "A3_A9_production_integrated_calibration_arms"
        ]
        is True
        and pareto_remediation_v8["production_integrated_arms"] == 4
        and pareto_remediation_v8["P3_complete"] is False
        and pareto_remediation_v8["prospective_trial_authorized"] is False,
        "Pareto remediation-v8 freeze changed",
    )
    require(
        iteration46["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration46["progress"][
            "shared_resource_receipt_overlay_ready"
        ]
        is True
        and iteration46["progress"][
            "A3_A9_complete_contract_batches_ready"
        ]
        is True
        and iteration46["progress"]["base_contract_pairs_accepted"] == 46
        and iteration46["progress"]["production_integrated_arms"] == 4
        and iteration46["progress"]["P3_complete"] is False
        and iteration46["authorization"]["prerequisites_passed"] == 4
        and iteration46["authorization"][
            "required_arms_production_integrated"
        ]
        == 4
        and iteration46["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.6 inflated verdict",
    )
    require(
        a1_compatibility["status"]
        == "A1_DIRECT_ADAPTER_REJECTED_INCOMPLETE_IR_SURFACE"
        and all(a1_compatibility["checks"].values())
        and len(a1_compatibility["A1_runtime_ops"]) == 22
        and a1_compatibility["mapping_counts"]["DIRECT_EXACT"] == 9
        and a1_compatibility["mapping_counts"][
            "CONDITIONAL_COMPOSITE"
        ]
        == 11
        and a1_compatibility["mapping_counts"]["UNSUPPORTED"] == 21
        and a1_compatibility["invocation_counts"]["DIRECT_EXACT"] == 143
        and a1_compatibility["invocation_counts"][
            "CONDITIONAL_COMPOSITE"
        ]
        == 114
        and a1_compatibility["invocation_counts"]["UNSUPPORTED"] == 80
        and a1_compatibility["summary"]["graphs"] == 23
        and a1_compatibility["summary"]["whole_graph_direct"] == 4
        and a1_compatibility["summary"][
            "exact_constructor_pattern_candidates"
        ]
        == 0
        and a1_compatibility["summary"]["production_adapter_ready"]
        is False
        and a1_compatibility["integration"][
            "production_integrated_arms"
        ]
        == 4
        and a1_compatibility["validation_v6_accessed"] is False,
        "A1 compatibility evidence changed",
    )
    require(
        a1_compatibility_resource["status"]
        == "A1_IR_COMPATIBILITY_RESOURCE_PASS"
        and all(a1_compatibility_resource["checks"].values())
        and a1_compatibility_resource["integration"][
            "A1_production_integrated"
        ]
        is False
        and a1_compatibility_resource["integration"][
            "production_integrated_arms"
        ]
        == 4
        and a1_compatibility_resource["P3"]["complete"] is False
        and a1_compatibility_resource["validation_v6_accessed"] is False,
        "A1 compatibility resource evidence changed",
    )
    require(
        len(pareto_remediation_v9["records"]) == 8
        and pareto_remediation_v9["phases"] == [93, 94]
        and pareto_remediation_v9["A1_runtime_ops"] == 22
        and pareto_remediation_v9["direct_exact_ATen_targets"] == 9
        and pareto_remediation_v9["direct_exact_calls"] == 143
        and pareto_remediation_v9["whole_graphs_direct"] == 4
        and pareto_remediation_v9[
            "exact_constructor_pattern_candidates"
        ]
        == 0
        and pareto_remediation_v9["A1_production_integrated"] is False
        and pareto_remediation_v9["production_integrated_arms"] == 4
        and pareto_remediation_v9["P3_complete"] is False
        and pareto_remediation_v9["prospective_trial_authorized"] is False,
        "Pareto remediation-v9 freeze changed",
    )
    require(
        iteration47["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration47["progress"]["A1_compatibility_audited"] is True
        and iteration47["progress"]["A1_runtime_ops"] == 22
        and iteration47["progress"]["A1_direct_exact_ATen_targets"] == 9
        and iteration47["progress"]["A1_direct_exact_calls"] == 143
        and iteration47["progress"]["A1_whole_graphs_direct"] == 4
        and iteration47["progress"][
            "A1_exact_constructor_pattern_candidates"
        ]
        == 0
        and iteration47["progress"]["A1_production_integrated"] is False
        and iteration47["progress"]["production_integrated_arms"] == 4
        and iteration47["progress"]["P3_complete"] is False
        and iteration47["authorization"]["prerequisites_passed"] == 4
        and iteration47["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.7 inflated verdict",
    )
    require(
        a4_replay["status"] == "A4_REPLAY_RUNTIME_CONFORMANCE_PASS"
        and all(a4_replay["checks"].values())
        and a4_replay["runtime_receipt"]["summary"]["graphs"] == 23
        and a4_replay["runtime_receipt"]["summary"][
            "unique_operator_targets"
        ]
        == 41
        and a4_replay["runtime_receipt"]["summary"][
            "call_function_invocations"
        ]
        == 337
        and a4_replay["runtime_receipt"]["summary"][
            "whole_graph_executions"
        ]
        == 69
        and a4_replay["runtime_receipt"]["summary"]["tools_replayed"] == 3
        and a4_replay["runtime_receipt"]["summary"][
            "successful_tool_replays"
        ]
        == 29
        and a4_replay["runtime_receipt"]["summary"]["max_tool_abs_error"]
        == a4_replay["runtime_receipt"]["summary"]["max_graph_abs_error"]
        == 0.0
        and a4_replay["integration"]["A4_production_integrated"] is False
        and a4_replay["validation_v6_accessed"] is False,
        "A4 replay runtime evidence changed",
    )
    require(
        a4_replay_resource["status"]
        == "A4_REPLAY_RUNTIME_RESOURCE_COMPONENT_PASS"
        and all(a4_replay_resource["checks"].values())
        and a4_replay_resource["integration"][
            "A4_complete_mount_process_tree_metered"
        ]
        is True
        and a4_replay_resource["integration"][
            "A4_production_integrated"
        ]
        is False
        and a4_replay_resource["validation_v6_accessed"] is False,
        "A4 replay resource evidence changed",
    )
    require(
        a4_batch["status"] == "A4_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(a4_batch["checks"].values())
        and len(a4_batch["hostile_rejections"]) == 11
        and all(
            row["rejected_twice"] for row in a4_batch["hostile_rejections"]
        )
        and a4_batch["primary"]["artifacts"]
        == a4_batch["independent"]["artifacts"]
        == 23
        and a4_batch["integration"]["production_integrated_arms"] == 5
        and a4_batch["P3"]["A4_complete_contract_batch_ready"] is True
        and a4_batch["P3"]["complete"] is False
        and a4_batch["validation_v6_accessed"] is False,
        "A4 shared batch evidence changed",
    )
    require(
        a4_batch_resource["status"]
        == "A4_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(a4_batch_resource["checks"].values())
        and a4_batch_resource["integration"][
            "A4_batch_assembly_process_tree_metered"
        ]
        is True
        and a4_batch_resource["integration"][
            "production_integrated_arms"
        ]
        == 5
        and a4_batch_resource["P3"]["complete"] is False
        and a4_batch_resource["validation_v6_accessed"] is False,
        "A4 shared batch resource evidence changed",
    )
    require(
        len(pareto_remediation_v10["records"]) == 15
        and pareto_remediation_v10["phases"] == [95, 96, 97, 98]
        and pareto_remediation_v10["A4_immutable_tools"] == 3
        and pareto_remediation_v10["A4_successful_tool_replays"] == 29
        and pareto_remediation_v10["A4_whole_graph_executions"] == 69
        and pareto_remediation_v10["A4_maximum_error"] == 0.0
        and pareto_remediation_v10[
            "A4_base_contract_pairs_accepted"
        ]
        == 23
        and pareto_remediation_v10[
            "A4_shared_resource_receipts_charged"
        ]
        == 1
        and pareto_remediation_v10[
            "A4_hostile_batches_rejected_twice"
        ]
        == 11
        and pareto_remediation_v10[
            "A4_production_integrated_calibration_arm"
        ]
        is True
        and pareto_remediation_v10["production_integrated_arms"] == 5
        and pareto_remediation_v10["P3_complete"] is False
        and pareto_remediation_v10["prospective_trial_authorized"]
        is False,
        "Pareto remediation-v10 freeze changed",
    )
    require(
        iteration48["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration48["progress"]["A4_runtime_mount_ready"] is True
        and iteration48["progress"]["A4_immutable_tools"] == 3
        and iteration48["progress"]["A4_successful_tool_replays"] == 29
        and iteration48["progress"]["A4_whole_graph_executions"] == 69
        and iteration48["progress"][
            "A4_base_contract_pairs_accepted"
        ]
        == 23
        and iteration48["progress"][
            "A4_production_integrated_calibration_arm"
        ]
        is True
        and iteration48["progress"]["production_integrated_arms"] == 5
        and iteration48["progress"]["P3_complete"] is False
        and iteration48["authorization"]["prerequisites_passed"] == 4
        and iteration48["authorization"][
            "required_arms_production_integrated"
        ]
        == 5
        and iteration48["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.8 inflated verdict",
    )
    require(
        a5_typed["status"] == "A5_STITCH_TYPED_GRAPH_COMPONENT_PASS"
        and all(a5_typed["checks"].values())
        and a5_typed["input"]["programs"] == 23
        and a5_typed["input"]["call_function_invocations"] == 337
        and a5_typed["observed"]["abstractions"] == 1
        and a5_typed["observed"]["cost_change"] == 66458
        and a5_typed["integration"]["A5_production_integrated"] is False
        and a5_typed["validation_v6_accessed"] is False,
        "A5 typed-graph evidence changed",
    )
    require(
        a5_typed_resource["status"]
        == "A5_STITCH_TYPED_GRAPH_RESOURCE_COMPONENT_PASS"
        and all(a5_typed_resource["checks"].values())
        and a5_typed_resource["integration"][
            "A5_production_integrated"
        ]
        is False
        and a5_typed_resource["validation_v6_accessed"] is False,
        "A5 typed-graph resource evidence changed",
    )
    require(
        a5_mount["status"] == "A5_STITCH_RUNTIME_CONFORMANCE_PASS"
        and all(a5_mount["checks"].values())
        and a5_mount["runtime_receipt"]["summary"][
            "normalized_expansions_byte_identical"
        ]
        == 23
        and a5_mount["runtime_receipt"]["summary"][
            "raw_encoder_bytes_identical"
        ]
        == 0
        and a5_mount["runtime_receipt"]["summary"][
            "structural_rewrite_uses"
        ]
        == 329
        and a5_mount["runtime_receipt"]["summary"][
            "whole_graph_executions"
        ]
        == 69
        and a5_mount["runtime_receipt"]["scientific_boundary"][
            "rewritten_stitch_program_executed_as_tensor_runtime"
        ]
        is False
        and a5_mount["integration"]["production_integrated_arms"] == 5
        and a5_mount["validation_v6_accessed"] is False,
        "A5 runtime mount evidence changed",
    )
    require(
        a5_mount_resource["status"]
        == "A5_STITCH_RUNTIME_RESOURCE_COMPONENT_PASS"
        and all(a5_mount_resource["checks"].values())
        and a5_mount_resource["integration"][
            "A5_production_integrated"
        ]
        is False
        and a5_mount_resource["validation_v6_accessed"] is False,
        "A5 runtime resource evidence changed",
    )
    require(
        a5_batch["status"] == "A5_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(a5_batch["checks"].values())
        and len(a5_batch["hostile_rejections"]) == 19
        and all(
            row["rejected_twice"]
            for row in a5_batch["hostile_rejections"]
        )
        and a5_batch["primary"]["direct_structural_uses"]
        == a5_batch["independent"]["direct_structural_uses"]
        == 329
        and a5_batch["integration"]["production_integrated_arms"] == 6
        and a5_batch["P3"]["complete"] is False
        and a5_batch["validation_v6_accessed"] is False,
        "A5 shared batch evidence changed",
    )
    require(
        a5_batch_resource["status"]
        == "A5_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(a5_batch_resource["checks"].values())
        and a5_batch_resource["integration"][
            "A5_production_integrated"
        ]
        is True
        and a5_batch_resource["integration"][
            "production_integrated_arms"
        ]
        == 6
        and a5_batch_resource["P3"]["complete"] is False
        and a5_batch_resource["validation_v6_accessed"] is False,
        "A5 shared batch resource evidence changed",
    )
    require(
        len(pareto_remediation_v11["records"]) == 26
        and pareto_remediation_v11["phases"]
        == [99, 100, 101, 102, 103, 104]
        and pareto_remediation_v11["A5_structural_rewrite_uses"] == 329
        and pareto_remediation_v11[
            "A5_unabstracted_nonempty_kwargs_calls"
        ]
        == 8
        and pareto_remediation_v11["A5_normalized_reconstructions"] == 23
        and pareto_remediation_v11[
            "A5_raw_encoder_byte_reconstructions"
        ]
        == 0
        and pareto_remediation_v11[
            "A5_rewritten_tensor_runtime_executed"
        ]
        is False
        and pareto_remediation_v11["A5_tensor_primitive_invented"]
        is False
        and pareto_remediation_v11["production_integrated_arms"] == 6
        and pareto_remediation_v11["P3_complete"] is False
        and pareto_remediation_v11["prospective_trial_authorized"]
        is False,
        "Pareto remediation-v11 freeze changed",
    )
    require(
        iteration49["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration49["progress"][
            "A5_production_integrated_calibration_structural_control"
        ]
        is True
        and iteration49["progress"]["A5_structural_rewrite_uses"] == 329
        and iteration49["progress"]["A5_tensor_primitive_invented"]
        is False
        and iteration49["progress"]["production_integrated_arms"] == 6
        and iteration49["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration49["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 4.9 inflated verdict",
    )
    require(
        a7_compatibility["status"] == "A7_DIRECT_ADAPTER_REJECTED"
        and all(a7_compatibility["checks"].values())
        and a7_compatibility["framework_surface"]["graphs"] == 23
        and a7_compatibility["framework_surface"][
            "unique_operator_targets"
        ]
        == 41
        and a7_compatibility["framework_surface"][
            "call_function_invocations"
        ]
        == 337
        and a7_compatibility["framework_surface"][
            "direct_call_matches"
        ]
        == 0
        and a7_compatibility["framework_surface"]["unsupported_calls"]
        == 337
        and a7_compatibility["compatibility"]["direct_adapter_possible"]
        is False
        and a7_compatibility["integration"]["A7_production_integrated"]
        is False
        and a7_compatibility["integration"]["production_integrated_arms"]
        == 6
        and a7_compatibility["validation_v6_accessed"] is False,
        "A7 compatibility evidence changed",
    )
    require(
        a7_compatibility_resource["status"]
        == "A7_COMPATIBILITY_RESOURCE_PASS"
        and all(a7_compatibility_resource["checks"].values())
        and a7_compatibility_resource["integration"][
            "A7_production_integrated"
        ]
        is False
        and a7_compatibility_resource["integration"][
            "production_integrated_arms"
        ]
        == 6
        and a7_compatibility_resource["P3"]["complete"] is False
        and a7_compatibility_resource["validation_v6_accessed"] is False,
        "A7 compatibility resource evidence changed",
    )
    require(
        len(pareto_remediation_v12["records"]) == 7
        and pareto_remediation_v12["phases"] == [105, 106]
        and pareto_remediation_v12["A7_direct_call_matches"] == 0
        and pareto_remediation_v12[
            "A7_new_tensor_domain_component_classes_required"
        ]
        == 8
        and pareto_remediation_v12["A7_direct_adapter_supported"]
        is False
        and pareto_remediation_v12["A7_production_integrated"] is False
        and pareto_remediation_v12["production_integrated_arms"] == 6
        and pareto_remediation_v12["P3_complete"] is False
        and pareto_remediation_v12["prospective_trial_authorized"]
        is False,
        "Pareto remediation-v12 freeze changed",
    )
    require(
        iteration50["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration50["progress"]["A7_compatibility_audited"] is True
        and iteration50["progress"]["A7_direct_adapter_supported"]
        is False
        and iteration50["progress"]["A7_direct_call_matches"] == 0
        and iteration50["progress"]["A7_production_integrated"] is False
        and iteration50["progress"]["production_integrated_arms"] == 6
        and iteration50["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration50["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.0 inflated verdict",
    )
    require(
        unsupported_matrix["status"]
        == "REQUIRED_UNSUPPORTED_MATRIX_COMPONENT_PASS"
        and all(unsupported_matrix["checks"].values())
        and len(unsupported_matrix["artifacts"]) == 23
        and len(unsupported_matrix["outcomes"]) == 92
        and {
            row["arm_id"] for row in unsupported_matrix["outcomes"]
        }
        == {"A1", "A6", "A7", "A8"}
        and all(
            row["status"] == "REQUIRED_UNSUPPORTED"
            for row in unsupported_matrix["outcomes"]
        )
        and unsupported_matrix["integration"][
            "newly_production_integrated_arms"
        ]
        == 0
        and unsupported_matrix["integration"][
            "production_integrated_arms"
        ]
        == 6
        and unsupported_matrix["P3"]["complete"] is False
        and unsupported_matrix["validation_v6_accessed"] is False,
        "required-unsupported matrix evidence changed",
    )
    require(
        unsupported_matrix_resource["status"]
        == "REQUIRED_UNSUPPORTED_MATRIX_RESOURCE_PASS"
        and all(unsupported_matrix_resource["checks"].values())
        and unsupported_matrix_resource["integration"][
            "matrix_process_tree_metered"
        ]
        is True
        and unsupported_matrix_resource["integration"][
            "production_integrated_arms"
        ]
        == 6
        and unsupported_matrix_resource["P3"]["complete"] is False
        and unsupported_matrix_resource["validation_v6_accessed"]
        is False,
        "required-unsupported matrix resource evidence changed",
    )
    require(
        unsupported_contract["status"]
        == "REQUIRED_UNSUPPORTED_CONTRACT_CONFORMANCE_PASS"
        and all(unsupported_contract["checks"].values())
        and unsupported_contract["primary"]["pairs"]
        == unsupported_contract["independent"]["pairs"]
        == 92
        and unsupported_contract["primary"]["allocated_cpu_ns"]
        == unsupported_contract["independent"]["allocated_cpu_ns"]
        and unsupported_contract["primary"]["allocated_cpu_ns"] > 0
        and len(unsupported_contract["hostile_rejections"]) == 25
        and all(
            row["rejected_twice"]
            for row in unsupported_contract["hostile_rejections"]
        )
        and unsupported_contract["integration"][
            "newly_conformant_arms"
        ]
        == 0
        and unsupported_contract["integration"][
            "newly_production_integrated_arms"
        ]
        == 0
        and unsupported_contract["integration"][
            "production_integrated_arms"
        ]
        == 6
        and unsupported_contract["P3"]["complete"] is True
        and unsupported_contract["validation_v6_accessed"] is False,
        "required-unsupported contract evidence changed",
    )
    require(
        unsupported_contract_resource["status"]
        == "REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE_PASS"
        and all(unsupported_contract_resource["checks"].values())
        and unsupported_contract_resource["integration"][
            "unsupported_batch_and_hostile_gate_metered"
        ]
        is True
        and unsupported_contract_resource["integration"][
            "newly_production_integrated_arms"
        ]
        == 0
        and unsupported_contract_resource["integration"][
            "production_integrated_arms"
        ]
        == 6
        and unsupported_contract_resource["P3"]["complete"] is True
        and unsupported_contract_resource["validation_v6_accessed"]
        is False,
        "required-unsupported contract resource evidence changed",
    )
    require(
        len(pareto_remediation_v13["records"]) == 14
        and pareto_remediation_v13["phases"] == [107, 108, 109, 110]
        and pareto_remediation_v13[
            "explicit_required_unsupported_arms"
        ]
        == ["A1", "A6", "A7", "A8"]
        and pareto_remediation_v13[
            "required_unsupported_contract_pairs"
        ]
        == 92
        and pareto_remediation_v13[
            "base_contract_primary_accepts"
        ]
        == pareto_remediation_v13[
            "base_contract_independent_accepts"
        ]
        == 92
        and pareto_remediation_v13[
            "hostile_batches_rejected_twice"
        ]
        == 25
        and pareto_remediation_v13["newly_conformant_arms"] == 0
        and pareto_remediation_v13[
            "newly_production_integrated_arms"
        ]
        == 0
        and pareto_remediation_v13["production_integrated_arms"] == 6
        and pareto_remediation_v13["P3_complete"] is True
        and pareto_remediation_v13["current_prerequisites_passed"] == 5
        and pareto_remediation_v13["prospective_trial_authorized"]
        is False,
        "Pareto remediation-v13 freeze changed",
    )
    require(
        iteration51["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration51["progress"]["P3_complete"] is True
        and iteration51["progress"][
            "required_unsupported_contract_pairs"
        ]
        == 92
        and iteration51["progress"]["newly_conformant_arms"] == 0
        and iteration51["progress"][
            "newly_production_integrated_arms"
        ]
        == 0
        and iteration51["progress"]["production_integrated_arms"] == 6
        and iteration51["prerequisites"][
            "P3_complete_resource_meter"
        ]
        is True
        and iteration51["authorization"]["prerequisites_passed"] == 5
        and iteration51["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration51["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.1 inflated verdict",
    )
    require(
        isamore_acquisition["status"]
        == "ISAMORE_SOURCE_ACQUISITION_COMPONENT_PASS"
        and isamore_acquisition["source_records_exact"] is True
        and isamore_acquisition["source_record_count"] == 29
        and isamore_acquisition[
            "recursive_submodule_identities_observed"
        ]
        is True
        and len(isamore_acquisition["submodule_gitlinks"]) == 4
        and isamore_acquisition["published_workload"]["present"] is True
        and isamore_acquisition["control_executed"] is False
        and isamore_acquisition["P1_complete"] is False
        and isamore_acquisition["validation_v6_accessed"] is False,
        "ISAMORE recursive source acquisition evidence changed",
    )
    require(
        isamore_build["status"]
        == "ISAMORE_BUILD_CLOSURE_AUTHENTICATED_STOP"
        and isamore_build["checks"][
            "offline_locked_metadata_resolved"
        ]
        is True
        and isamore_build["checks"]["offline_locked_build_attempted"]
        is True
        and isamore_build["checks"][
            "first_missing_registry_package_authenticated"
        ]
        is True
        and isamore_build["checks"]["route_buildable"] is False
        and isamore_build["first_build_stop"]["package"] == "colored"
        and isamore_build["control_executed"] is False
        and isamore_build["P1_complete"] is False
        and isamore_build["validation_v6_accessed"] is False,
        "ISAMORE offline build-closure evidence changed",
    )
    require(
        len(isamore_acquisition_v2["records"]) == 5
        and isamore_acquisition_v2["phases"] == [111, 112]
        and isamore_acquisition_v2["source_record_count"] == 29
        and isamore_acquisition_v2["submodule_gitlinks_observed"] == 4
        and isamore_acquisition_v2[
            "offline_locked_metadata_resolved"
        ]
        is True
        and isamore_acquisition_v2[
            "offline_locked_build_attempted"
        ]
        is True
        and isamore_acquisition_v2["route_buildable"] is False
        and isamore_acquisition_v2["control_executed"] is False
        and isamore_acquisition_v2["P1_complete"] is False
        and isamore_acquisition_v2["prospective_trial_authorized"]
        is False,
        "ISAMORE acquisition-v2 freeze changed",
    )
    require(
        iteration52["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration52["progress"]["P1_complete"] is False
        and iteration52["progress"][
            "isamore_top_level_source_materialized"
        ]
        is True
        and iteration52["progress"][
            "isamore_recursive_gitlinks_observed"
        ]
        == 4
        and iteration52["progress"][
            "isamore_authenticated_source_records"
        ]
        == 29
        and iteration52["progress"]["isamore_control_executed"]
        is False
        and iteration52["progress"][
            "source_faithful_controls_reproduced"
        ]
        == 3
        and iteration52["authorization"]["prerequisites_passed"] == 5
        and iteration52["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration52["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.2 inflated verdict",
    )
    require(
        isamore_colored_bridge["status"]
        == "ISAMORE_AUXILIARY_DEPENDENCY_BRIDGE_ADVANCES_STOP"
        and isamore_colored_bridge["bridge"]["package"] == "colored"
        and isamore_colored_bridge["bridge"]["version"] == "3.1.1"
        and isamore_colored_bridge["bridge"][
            "source_records_exact_to_official_tag"
        ]
        is True
        and isamore_colored_bridge["bridge"][
            "crates_io_tarball_checksum_authenticated"
        ]
        is False
        and isamore_colored_bridge["checks"]["colored_stop_cleared"]
        is True
        and isamore_colored_bridge["checks"][
            "next_missing_package_authenticated"
        ]
        is True
        and isamore_colored_bridge["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_colored_bridge["next_build_stop"]["package"]
        == "crossbeam"
        and isamore_colored_bridge["control_executed"] is False,
        "ISAMORE colored bridge evidence changed",
    )
    require(
        len(isamore_dependency_bridge_v3["records"]) == 3
        and isamore_dependency_bridge_v3["phases"] == [113]
        and isamore_dependency_bridge_v3["bridged_package"]
        == "colored"
        and isamore_dependency_bridge_v3["prior_stop"] == "colored"
        and isamore_dependency_bridge_v3["next_stop"] == "crossbeam"
        and isamore_dependency_bridge_v3[
            "algorithm_execution_reached"
        ]
        is False
        and isamore_dependency_bridge_v3["P1_complete"] is False
        and isamore_dependency_bridge_v3[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v3 freeze changed",
    )
    require(
        iteration53["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration53["progress"]["P1_complete"] is False
        and iteration53["progress"][
            "isamore_offline_build_stop_before_bridge"
        ]
        == "colored"
        and iteration53["progress"][
            "isamore_offline_build_stop_after_bridge"
        ]
        == "crossbeam"
        and iteration53["progress"][
            "isamore_algorithm_compilation_reached"
        ]
        is False
        and iteration53["progress"]["isamore_control_executed"]
        is False
        and iteration53["authorization"]["prerequisites_passed"] == 5
        and iteration53["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration53["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.3 inflated verdict",
    )
    require(
        isamore_crossbeam_bridge["status"]
        == "ISAMORE_CROSSBEAM_CLOSURE_ADVANCES_STOP"
        and isamore_crossbeam_bridge["bridge"]["package"] == "crossbeam"
        and isamore_crossbeam_bridge["bridge"]["version"] == "0.8.4"
        and len(
            isamore_crossbeam_bridge["bridge"]["official_tag_records"]
        )
        == 6
        and len(
            isamore_crossbeam_bridge["bridge"][
                "locked_cached_archive_records"
            ]
        )
        == 4
        and isamore_crossbeam_bridge["bridge"][
            "root_and_queue_crates_io_checksums_authenticated"
        ]
        is False
        and isamore_crossbeam_bridge["checks"]["crossbeam_stop_cleared"]
        is True
        and isamore_crossbeam_bridge["checks"][
            "next_missing_package_authenticated"
        ]
        is True
        and isamore_crossbeam_bridge["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_crossbeam_bridge["checks"][
            "algorithm_execution_reached"
        ]
        is False
        and isamore_crossbeam_bridge["next_build_stop"]["package"] == "csv"
        and isamore_crossbeam_bridge["control_executed"] is False
        and isamore_crossbeam_bridge["P1_complete"] is False
        and isamore_crossbeam_bridge["validation_v6_accessed"] is False,
        "ISAMORE Crossbeam bridge evidence changed",
    )
    require(
        len(isamore_dependency_bridge_v4["records"]) == 3
        and isamore_dependency_bridge_v4["phases"] == [114]
        and isamore_dependency_bridge_v4["bridged_package"] == "crossbeam"
        and isamore_dependency_bridge_v4["bridged_version"] == "0.8.4"
        and isamore_dependency_bridge_v4["prior_stop"] == "crossbeam"
        and isamore_dependency_bridge_v4["next_stop"] == "csv"
        and isamore_dependency_bridge_v4[
            "algorithm_execution_reached"
        ]
        is False
        and isamore_dependency_bridge_v4["P1_complete"] is False
        and isamore_dependency_bridge_v4[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v4 freeze changed",
    )
    require(
        iteration54["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration54["progress"]["P1_complete"] is False
        and iteration54["progress"][
            "isamore_offline_build_stop_before_bridge"
        ]
        == "crossbeam"
        and iteration54["progress"][
            "isamore_offline_build_stop_after_bridge"
        ]
        == "csv"
        and iteration54["progress"]["isamore_auxiliary_packages_bridged"]
        == 2
        and iteration54["progress"][
            "isamore_algorithm_compilation_reached"
        ]
        is False
        and iteration54["progress"]["isamore_control_executed"] is False
        and iteration54["authorization"]["prerequisites_passed"] == 5
        and iteration54["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration54["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.4 inflated verdict",
    )
    require(
        isamore_csv_closure["status"]
        == "ISAMORE_CSV_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and isamore_csv_closure["root_package"]
        == {"package": "csv", "version": "1.4.0"}
        and isamore_csv_closure["summary"]["locked_packages"] == 11
        and isamore_csv_closure["summary"]["exact_cached_archives"] == 7
        and isamore_csv_closure["summary"]["missing_exact_archives"] == 4
        and {
            (row["package"], row["version"])
            for row in isamore_csv_closure["missing_exact_packages"]
        }
        == {
            ("csv", "1.4.0"),
            ("csv-core", "0.1.13"),
            ("itoa", "1.0.17"),
            ("quote", "1.0.44"),
        }
        and isamore_csv_closure["nearby_versions_rejected"]["itoa"][
            "available_but_not_substituted"
        ]
        == "1.0.18"
        and isamore_csv_closure["nearby_versions_rejected"]["quote"][
            "available_but_not_substituted"
        ]
        == "1.0.45"
        and isamore_csv_closure["build_stop_after_phase"] == "csv"
        and isamore_csv_closure["algorithm_compilation_reached"] is False
        and isamore_csv_closure["algorithm_execution_reached"] is False
        and isamore_csv_closure["control_executed"] is False
        and isamore_csv_closure["P1_complete"] is False
        and isamore_csv_closure["validation_v6_accessed"] is False,
        "ISAMORE csv closure census changed",
    )
    require(
        len(isamore_dependency_bridge_v5["records"]) == 3
        and isamore_dependency_bridge_v5["phases"] == [115]
        and isamore_dependency_bridge_v5["closure_root"] == "csv 1.4.0"
        and isamore_dependency_bridge_v5["locked_packages"] == 11
        and isamore_dependency_bridge_v5["exact_cached_archives"] == 7
        and isamore_dependency_bridge_v5["missing_exact_archives"] == 4
        and isamore_dependency_bridge_v5["prior_stop"] == "csv"
        and isamore_dependency_bridge_v5["next_stop"] == "csv"
        and isamore_dependency_bridge_v5[
            "algorithm_execution_reached"
        ]
        is False
        and isamore_dependency_bridge_v5["P1_complete"] is False
        and isamore_dependency_bridge_v5[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v5 freeze changed",
    )
    require(
        iteration55["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration55["progress"]["P1_complete"] is False
        and iteration55["progress"][
            "isamore_offline_build_stop_before_phase"
        ]
        == "csv"
        and iteration55["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "csv"
        and iteration55["progress"][
            "isamore_csv_exact_cached_archives"
        ]
        == 7
        and iteration55["progress"][
            "isamore_csv_missing_exact_archives"
        ]
        == 4
        and iteration55["progress"]["isamore_control_executed"] is False
        and iteration55["authorization"]["prerequisites_passed"] == 5
        and iteration55["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration55["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.5 inflated verdict",
    )
    require(
        isamore_csv_tag_bridge["status"]
        == "ISAMORE_CSV_CLOSURE_ADVANCES_STOP"
        and len(isamore_csv_tag_bridge["bridge"]["official_tag_records"])
        == 27
        and isamore_csv_tag_bridge["bridge"][
            "crates_io_tarball_checksums_authenticated"
        ]
        is False
        and isamore_csv_tag_bridge["checks"][
            "manifest_versions_match_lock"
        ]
        is True
        and isamore_csv_tag_bridge["checks"][
            "nearby_versions_substituted"
        ]
        is False
        and isamore_csv_tag_bridge["checks"]["csv_stop_cleared"] is True
        and isamore_csv_tag_bridge["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_csv_tag_bridge["next_build_stop"]["package"]
        == "env_logger"
        and isamore_csv_tag_bridge["control_executed"] is False
        and isamore_csv_tag_bridge["validation_v6_accessed"] is False,
        "ISAMORE csv tag bridge evidence changed",
    )
    require(
        len(isamore_dependency_bridge_v6["records"]) == 3
        and isamore_dependency_bridge_v6["phases"] == [116]
        and isamore_dependency_bridge_v6["official_tag_records"] == 27
        and isamore_dependency_bridge_v6["prior_stop"] == "csv"
        and isamore_dependency_bridge_v6["next_stop"] == "env_logger"
        and isamore_dependency_bridge_v6[
            "algorithm_execution_reached"
        ]
        is False
        and isamore_dependency_bridge_v6["P1_complete"] is False
        and isamore_dependency_bridge_v6[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v6 freeze changed",
    )
    require(
        iteration56["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration56["progress"][
            "isamore_offline_build_stop_before_phase"
        ]
        == "csv"
        and iteration56["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "env_logger"
        and iteration56["progress"]["isamore_control_executed"] is False
        and iteration56["authorization"]["prerequisites_passed"] == 5
        and iteration56["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration56["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.6 inflated verdict",
    )
    require(
        isamore_env_logger_closure["status"]
        == "ISAMORE_ENV_LOGGER_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and len(isamore_env_logger_closure["root_packages"]) == 3
        and isamore_env_logger_closure["summary"]["root_versions"] == 3
        and isamore_env_logger_closure["summary"]["locked_packages"] == 31
        and isamore_env_logger_closure["summary"][
            "exact_cached_archives"
        ]
        == 14
        and isamore_env_logger_closure["summary"][
            "missing_exact_archives"
        ]
        == 17
        and isamore_env_logger_closure["single_version_patch_rejected"]
        is True
        and isamore_env_logger_closure["build_stop_after_phase"]
        == "env_logger"
        and isamore_env_logger_closure["algorithm_compilation_reached"]
        is False
        and isamore_env_logger_closure["control_executed"] is False
        and isamore_env_logger_closure["validation_v6_accessed"] is False,
        "ISAMORE env_logger closure census changed",
    )
    require(
        len(isamore_dependency_bridge_v7["records"]) == 3
        and isamore_dependency_bridge_v7["phases"] == [117]
        and isamore_dependency_bridge_v7["root_versions"] == 3
        and isamore_dependency_bridge_v7["locked_packages"] == 31
        and isamore_dependency_bridge_v7["exact_cached_archives"] == 14
        and isamore_dependency_bridge_v7["missing_exact_archives"] == 17
        and isamore_dependency_bridge_v7["prior_stop"] == "env_logger"
        and isamore_dependency_bridge_v7["next_stop"] == "env_logger"
        and isamore_dependency_bridge_v7["control_executed"] is False
        and isamore_dependency_bridge_v7["P1_complete"] is False
        and isamore_dependency_bridge_v7[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v7 freeze changed",
    )
    require(
        iteration57["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration57["progress"]["isamore_env_logger_root_versions"]
        == 3
        and iteration57["progress"][
            "isamore_env_logger_union_closure_packages"
        ]
        == 31
        and iteration57["progress"][
            "isamore_env_logger_exact_cached_archives"
        ]
        == 14
        and iteration57["progress"][
            "isamore_env_logger_missing_exact_archives"
        ]
        == 17
        and iteration57["progress"]["isamore_control_executed"] is False
        and iteration57["authorization"]["prerequisites_passed"] == 5
        and iteration57["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration57["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.7 inflated verdict",
    )
    require(
        isamore_env_logger_roots["status"]
        == "ISAMORE_ENV_LOGGER_ROOTS_ADVANCE_STOP"
        and isamore_env_logger_roots["bridge"]["versions"]
        == ["0.7.1", "0.9.3", "0.11.9"]
        and isamore_env_logger_roots["bridge"]["record_count"] == 37
        and len(
            isamore_env_logger_roots["bridge"]["multi_version_aliases"]
        )
        == 3
        and isamore_env_logger_roots["bridge"][
            "crates_io_tarball_checksums_authenticated"
        ]
        is False
        and isamore_env_logger_roots["checks"][
            "all_three_manifest_versions_match_lock"
        ]
        is True
        and isamore_env_logger_roots["checks"][
            "single_version_substitution"
        ]
        is False
        and isamore_env_logger_roots["checks"][
            "env_logger_stop_cleared"
        ]
        is True
        and isamore_env_logger_roots["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_env_logger_roots["next_build_stop"]["package"]
        == "graphviz-rust"
        and isamore_env_logger_roots["control_executed"] is False
        and isamore_env_logger_roots["validation_v6_accessed"] is False,
        "ISAMORE env_logger roots bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v8["records"]) == 3
        and isamore_dependency_bridge_v8["phases"] == [118]
        and isamore_dependency_bridge_v8["root_versions"] == 3
        and isamore_dependency_bridge_v8["official_tag_records"] == 37
        and isamore_dependency_bridge_v8["prior_stop"] == "env_logger"
        and isamore_dependency_bridge_v8["next_stop"] == "graphviz-rust"
        and isamore_dependency_bridge_v8["control_executed"] is False
        and isamore_dependency_bridge_v8["P1_complete"] is False
        and isamore_dependency_bridge_v8[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v8 freeze changed",
    )
    require(
        iteration58["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration58["progress"][
            "isamore_env_logger_tag_roots_mounted"
        ]
        == 3
        and iteration58["progress"]["isamore_env_logger_tag_records"] == 37
        and iteration58["progress"][
            "isamore_offline_build_stop_before_phase"
        ]
        == "env_logger"
        and iteration58["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "graphviz-rust"
        and iteration58["progress"]["isamore_control_executed"] is False
        and iteration58["authorization"]["prerequisites_passed"] == 5
        and iteration58["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration58["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.8 inflated verdict",
    )
    require(
        isamore_graphviz_closure["status"]
        == "ISAMORE_GRAPHVIZ_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and isamore_graphviz_closure["root_package"]
        == {"package": "graphviz-rust", "version": "0.8.0"}
        and isamore_graphviz_closure["summary"]["locked_packages"] == 77
        and isamore_graphviz_closure["summary"][
            "exact_cached_archives"
        ]
        == 57
        and isamore_graphviz_closure["summary"][
            "missing_exact_archives"
        ]
        == 20
        and len(isamore_graphviz_closure["missing_exact_packages"]) == 20
        and isamore_graphviz_closure["build_stop_after_phase"]
        == "graphviz-rust"
        and isamore_graphviz_closure["algorithm_compilation_reached"]
        is False
        and isamore_graphviz_closure["control_executed"] is False
        and isamore_graphviz_closure["validation_v6_accessed"] is False,
        "ISAMORE graphviz closure census changed",
    )
    require(
        len(isamore_dependency_bridge_v9["records"]) == 3
        and isamore_dependency_bridge_v9["phases"] == [119]
        and isamore_dependency_bridge_v9["closure_root"]
        == "graphviz-rust 0.8.0"
        and isamore_dependency_bridge_v9["locked_packages"] == 77
        and isamore_dependency_bridge_v9["exact_cached_archives"] == 57
        and isamore_dependency_bridge_v9["missing_exact_archives"] == 20
        and isamore_dependency_bridge_v9["prior_stop"] == "graphviz-rust"
        and isamore_dependency_bridge_v9["next_stop"] == "graphviz-rust"
        and isamore_dependency_bridge_v9["control_executed"] is False
        and isamore_dependency_bridge_v9[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v9 freeze changed",
    )
    require(
        iteration59["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration59["progress"][
            "isamore_graphviz_locked_closure_packages"
        ]
        == 77
        and iteration59["progress"][
            "isamore_graphviz_exact_cached_archives"
        ]
        == 57
        and iteration59["progress"][
            "isamore_graphviz_missing_exact_archives"
        ]
        == 20
        and iteration59["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "graphviz-rust"
        and iteration59["progress"]["isamore_control_executed"] is False
        and iteration59["authorization"]["prerequisites_passed"] == 5
        and iteration59["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration59["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.9 inflated verdict",
    )
    require(
        isamore_graphviz_bridge["status"]
        == "ISAMORE_GRAPHVIZ_FAMILY_ADVANCES_STOP"
        and len(isamore_graphviz_bridge["bridge"]["packages"]) == 5
        and isamore_graphviz_bridge["bridge"]["record_count"] == 16
        and len(isamore_graphviz_bridge["bridge"]["revisions"]) == 2
        and isamore_graphviz_bridge["bridge"]["release_tag_resolved"]
        is False
        and isamore_graphviz_bridge["bridge"][
            "crates_io_tarball_checksums_authenticated"
        ]
        is False
        and isamore_graphviz_bridge["checks"][
            "all_five_manifest_versions_match_lock"
        ]
        is True
        and isamore_graphviz_bridge["checks"]["graphviz_stop_cleared"]
        is True
        and isamore_graphviz_bridge["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_graphviz_bridge["next_build_stop"]["package"]
        == "indicatif"
        and isamore_graphviz_bridge["control_executed"] is False
        and isamore_graphviz_bridge["validation_v6_accessed"] is False,
        "ISAMORE graphviz family bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v10["records"]) == 3
        and isamore_dependency_bridge_v10["phases"] == [120]
        and isamore_dependency_bridge_v10["bridged_packages"] == 5
        and isamore_dependency_bridge_v10["source_records"] == 16
        and isamore_dependency_bridge_v10["prior_stop"] == "graphviz-rust"
        and isamore_dependency_bridge_v10["next_stop"] == "indicatif"
        and isamore_dependency_bridge_v10["control_executed"] is False
        and isamore_dependency_bridge_v10["P1_complete"] is False
        and isamore_dependency_bridge_v10[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v10 freeze changed",
    )
    require(
        iteration510["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration510["progress"][
            "isamore_graphviz_family_packages_bridged"
        ]
        == 5
        and iteration510["progress"][
            "isamore_graphviz_family_source_records"
        ]
        == 16
        and iteration510["progress"][
            "isamore_offline_build_stop_before_phase"
        ]
        == "graphviz-rust"
        and iteration510["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "indicatif"
        and iteration510["progress"]["isamore_control_executed"] is False
        and iteration510["authorization"]["prerequisites_passed"] == 5
        and iteration510["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration510["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.10 inflated verdict",
    )
    require(
        isamore_indicatif_closure["status"]
        == "ISAMORE_INDICATIF_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and isamore_indicatif_closure["root_package"]
        == {"package": "indicatif", "version": "0.17.11"}
        and isamore_indicatif_closure["summary"]["locked_packages"] == 31
        and isamore_indicatif_closure["summary"]["exact_cached_archives"]
        == 18
        and isamore_indicatif_closure["summary"]["missing_exact_archives"]
        == 13
        and len(isamore_indicatif_closure["missing_exact_packages"]) == 13
        and isamore_indicatif_closure[
            "already_bridged_quote_tag_not_counted_as_archive"
        ]
        is True
        and isamore_indicatif_closure["build_stop_after_phase"]
        == "indicatif"
        and isamore_indicatif_closure["algorithm_compilation_reached"]
        is False
        and isamore_indicatif_closure["algorithm_execution_reached"]
        is False
        and isamore_indicatif_closure["control_executed"] is False
        and isamore_indicatif_closure["P1_complete"] is False
        and isamore_indicatif_closure["validation_v6_accessed"] is False
        and isamore_indicatif_closure["prospective_trial_authorized"]
        is False,
        "ISAMORE indicatif closure census changed",
    )
    require(
        len(isamore_dependency_bridge_v11["records"]) == 3
        and isamore_dependency_bridge_v11["phases"] == [121]
        and isamore_dependency_bridge_v11["closure_root"]
        == "indicatif 0.17.11"
        and isamore_dependency_bridge_v11["locked_packages"] == 31
        and isamore_dependency_bridge_v11["exact_cached_archives"] == 18
        and isamore_dependency_bridge_v11["missing_exact_archives"] == 13
        and isamore_dependency_bridge_v11["prior_stop"] == "indicatif"
        and isamore_dependency_bridge_v11["next_stop"] == "indicatif"
        and isamore_dependency_bridge_v11["control_executed"] is False
        and isamore_dependency_bridge_v11["P1_complete"] is False
        and isamore_dependency_bridge_v11[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v11 freeze changed",
    )
    require(
        iteration511["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration511["progress"][
            "isamore_indicatif_locked_closure_packages"
        ]
        == 31
        and iteration511["progress"][
            "isamore_indicatif_exact_cached_archives"
        ]
        == 18
        and iteration511["progress"][
            "isamore_indicatif_missing_exact_archives"
        ]
        == 13
        and iteration511["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "indicatif"
        and iteration511["progress"]["isamore_control_executed"] is False
        and iteration511["authorization"]["prerequisites_passed"] == 5
        and iteration511["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration511["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.11 inflated verdict",
    )
    require(
        isamore_indicatif_bridge["status"]
        == "ISAMORE_INDICATIF_FAMILY_ADVANCES_STOP"
        and len(isamore_indicatif_bridge["bridge"]["packages"]) == 4
        and isamore_indicatif_bridge["bridge"]["record_count"] == 35
        and isamore_indicatif_bridge["bridge"]["all_release_tags_resolved"]
        is True
        and isamore_indicatif_bridge["bridge"][
            "crates_io_tarball_checksums_authenticated"
        ]
        is False
        and isamore_indicatif_bridge["checks"][
            "all_manifest_versions_match_lock"
        ]
        is True
        and isamore_indicatif_bridge["checks"][
            "all_source_records_match_official_tags"
        ]
        is True
        and isamore_indicatif_bridge["checks"]["indicatif_stop_cleared"]
        is True
        and isamore_indicatif_bridge["next_build_stop"]["package"] == "kiddo"
        and isamore_indicatif_bridge["checks"][
            "algorithm_compilation_reached"
        ]
        is False
        and isamore_indicatif_bridge["control_executed"] is False
        and isamore_indicatif_bridge["validation_v6_accessed"] is False,
        "ISAMORE indicatif family bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v12["records"]) == 3
        and isamore_dependency_bridge_v12["phases"] == [122]
        and isamore_dependency_bridge_v12["bridged_packages"] == 4
        and isamore_dependency_bridge_v12["source_records"] == 35
        and isamore_dependency_bridge_v12["prior_stop"] == "indicatif"
        and isamore_dependency_bridge_v12["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v12["control_executed"] is False
        and isamore_dependency_bridge_v12["P1_complete"] is False
        and isamore_dependency_bridge_v12[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v12 freeze changed",
    )
    require(
        iteration512["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration512["progress"][
            "isamore_indicatif_family_packages_bridged"
        ]
        == 4
        and iteration512["progress"][
            "isamore_indicatif_family_source_records"
        ]
        == 35
        and iteration512["progress"][
            "isamore_offline_build_stop_before_phase"
        ]
        == "indicatif"
        and iteration512["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "kiddo"
        and iteration512["progress"]["isamore_control_executed"] is False
        and iteration512["authorization"]["prerequisites_passed"] == 5
        and iteration512["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration512["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.12 inflated verdict",
    )
    require(
        isamore_kiddo_closure["status"]
        == "ISAMORE_KIDDO_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and isamore_kiddo_closure["root_package"]
        == {"package": "kiddo", "version": "5.2.4"}
        and isamore_kiddo_closure["summary"]["locked_packages"] == 56
        and isamore_kiddo_closure["summary"]["exact_cached_archives"] == 34
        and isamore_kiddo_closure["summary"]["missing_exact_archives"] == 22
        and len(isamore_kiddo_closure["missing_exact_packages"]) == 22
        and isamore_kiddo_closure[
            "prior_tag_sources_not_counted_as_archive_identity"
        ]
        is True
        and isamore_kiddo_closure["build_stop_after_phase"] == "kiddo"
        and isamore_kiddo_closure["algorithm_compilation_reached"] is False
        and isamore_kiddo_closure["algorithm_execution_reached"] is False
        and isamore_kiddo_closure["control_executed"] is False
        and isamore_kiddo_closure["P1_complete"] is False
        and isamore_kiddo_closure["validation_v6_accessed"] is False
        and isamore_kiddo_closure["prospective_trial_authorized"] is False,
        "ISAMORE kiddo closure census changed",
    )
    require(
        len(isamore_dependency_bridge_v13["records"]) == 3
        and isamore_dependency_bridge_v13["phases"] == [123]
        and isamore_dependency_bridge_v13["closure_root"] == "kiddo 5.2.4"
        and isamore_dependency_bridge_v13["locked_packages"] == 56
        and isamore_dependency_bridge_v13["exact_cached_archives"] == 34
        and isamore_dependency_bridge_v13["missing_exact_archives"] == 22
        and isamore_dependency_bridge_v13["prior_stop"] == "kiddo"
        and isamore_dependency_bridge_v13["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v13["control_executed"] is False
        and isamore_dependency_bridge_v13["P1_complete"] is False
        and isamore_dependency_bridge_v13[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v13 freeze changed",
    )
    require(
        iteration513["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration513["progress"]["isamore_kiddo_locked_closure_packages"]
        == 56
        and iteration513["progress"]["isamore_kiddo_exact_cached_archives"]
        == 34
        and iteration513["progress"]["isamore_kiddo_missing_exact_archives"]
        == 22
        and iteration513["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "kiddo"
        and iteration513["progress"]["isamore_control_executed"] is False
        and iteration513["authorization"]["prerequisites_passed"] == 5
        and iteration513["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration513["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.13 inflated verdict",
    )
    require(
        isamore_kiddo_partial_bridge["status"]
        == "ISAMORE_KIDDO_PARTIAL_FAMILY_AUTHENTICATED_NO_STOP_ADVANCE"
        and len(isamore_kiddo_partial_bridge["bridge"]["packages"]) == 3
        and isamore_kiddo_partial_bridge["bridge"]["record_count"] == 13
        and isamore_kiddo_partial_bridge["bridge"]["exact_release_tags"] == 2
        and isamore_kiddo_partial_bridge["bridge"][
            "pinned_official_publish_commits"
        ]
        == 1
        and isamore_kiddo_partial_bridge["bridge"][
            "crates_io_tarball_checksums_authenticated"
        ]
        is False
        and isamore_kiddo_partial_bridge["checks"][
            "all_manifest_versions_match_lock"
        ]
        is True
        and isamore_kiddo_partial_bridge["checks"][
            "all_source_records_match_upstream"
        ]
        is True
        and isamore_kiddo_partial_bridge["checks"][
            "resolver_stop_unchanged"
        ]
        is True
        and isamore_kiddo_partial_bridge["checks"][
            "kiddo_root_source_acquired"
        ]
        is False
        and isamore_kiddo_partial_bridge["next_build_stop"]["package"]
        == "kiddo"
        and isamore_kiddo_partial_bridge["control_executed"] is False
        and isamore_kiddo_partial_bridge["validation_v6_accessed"] is False,
        "ISAMORE partial kiddo-family bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v14["records"]) == 3
        and isamore_dependency_bridge_v14["phases"] == [124]
        and isamore_dependency_bridge_v14["bridged_packages"] == 3
        and isamore_dependency_bridge_v14["source_records"] == 13
        and isamore_dependency_bridge_v14["prior_stop"] == "kiddo"
        and isamore_dependency_bridge_v14["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v14["kiddo_root_source_acquired"]
        is False
        and isamore_dependency_bridge_v14["control_executed"] is False
        and isamore_dependency_bridge_v14["P1_complete"] is False
        and isamore_dependency_bridge_v14[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v14 freeze changed",
    )
    require(
        iteration514["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration514["progress"][
            "isamore_kiddo_partial_family_packages_bridged"
        ]
        == 3
        and iteration514["progress"][
            "isamore_kiddo_partial_family_source_records"
        ]
        == 13
        and iteration514["progress"]["isamore_kiddo_root_source_acquired"]
        is False
        and iteration514["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "kiddo"
        and iteration514["progress"]["isamore_control_executed"] is False
        and iteration514["authorization"]["prerequisites_passed"] == 5
        and iteration514["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration514["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.14 inflated verdict",
    )
    require(
        isamore_kiddo_root_acquisition["status"]
        == "ISAMORE_KIDDO_ROOT_AVAILABLE_CHANNELS_AUDITED_NO_SOURCE"
        and isamore_kiddo_root_acquisition["locked_root"]["version"] == "5.2.4"
        and isamore_kiddo_root_acquisition["locked_root"]["sha256"]
        == "07ab03cc75e18eb1eec59f4037e2e17ce9d13920f0013b0719dea613d9414e4e"
        and isamore_kiddo_root_acquisition[
            "official_repository_evidence"
        ]["manifest_declared_version"]
        == "5.2.1"
        and isamore_kiddo_root_acquisition[
            "official_repository_evidence"
        ]["manifest_git_blob_sha1"]
        == "1f5e83b6e242fb98db8ab33fd256e889e7854af7"
        and isamore_kiddo_root_acquisition["checks"][
            "release_adjacent_manifest_matches_locked_version"
        ]
        is False
        and isamore_kiddo_root_acquisition["checks"][
            "shell_registry_transport_available"
        ]
        is False
        and isamore_kiddo_root_acquisition["checks"][
            "kiddo_root_source_acquired"
        ]
        is False
        and isamore_kiddo_root_acquisition["next_build_stop"]["package"]
        == "kiddo"
        and isamore_kiddo_root_acquisition["control_executed"] is False
        and isamore_kiddo_root_acquisition["validation_v6_accessed"] is False,
        "ISAMORE kiddo-root acquisition boundary changed",
    )
    require(
        len(isamore_dependency_bridge_v15["records"]) == 4
        and isamore_dependency_bridge_v15["phases"] == [125]
        and isamore_dependency_bridge_v15["locked_root"] == "kiddo 5.2.4"
        and isamore_dependency_bridge_v15[
            "release_adjacent_manifest_version"
        ]
        == "5.2.1"
        and isamore_dependency_bridge_v15["prior_stop"] == "kiddo"
        and isamore_dependency_bridge_v15["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v15["kiddo_root_source_acquired"]
        is False
        and isamore_dependency_bridge_v15["control_executed"] is False
        and isamore_dependency_bridge_v15[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v15 freeze changed",
    )
    require(
        iteration515["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration515["progress"][
            "isamore_kiddo_root_acquisition_channels_audited"
        ]
        is True
        and iteration515["progress"][
            "isamore_kiddo_release_adjacent_manifest_version"
        ]
        == "5.2.1"
        and iteration515["progress"]["isamore_kiddo_root_source_acquired"]
        is False
        and iteration515["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "kiddo"
        and iteration515["authorization"]["prerequisites_passed"] == 5
        and iteration515["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration515["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.15 inflated verdict",
    )
    require(
        isamore_divrem_bridge["status"]
        == "ISAMORE_DIVREM_EXACT_TAG_AUTHENTICATED_NO_STOP_ADVANCE"
        and isamore_divrem_bridge["bridge"]["package"] == "divrem"
        and isamore_divrem_bridge["bridge"]["version"] == "1.0.0"
        and isamore_divrem_bridge["bridge"]["revision"] == "1.0.0"
        and isamore_divrem_bridge["bridge"]["record_count"] == 7
        and isamore_divrem_bridge["checks"]["source_compilation_passed"]
        is True
        and isamore_divrem_bridge["checks"]["resolver_stop_unchanged"]
        is True
        and isamore_divrem_bridge["checks"]["kiddo_root_source_acquired"]
        is False
        and isamore_divrem_bridge["accumulated_kiddo_family"][
            "packages_bridged"
        ]
        == 4
        and isamore_divrem_bridge["accumulated_kiddo_family"][
            "source_records_authenticated"
        ]
        == 20
        and isamore_divrem_bridge["next_build_stop"]["package"] == "kiddo"
        and isamore_divrem_bridge["control_executed"] is False
        and isamore_divrem_bridge["validation_v6_accessed"] is False,
        "ISAMORE exact divrem-family bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v16["records"]) == 10
        and isamore_dependency_bridge_v16["phases"] == [126]
        and isamore_dependency_bridge_v16["bridged_package"]
        == "divrem 1.0.0"
        and isamore_dependency_bridge_v16["source_records"] == 7
        and isamore_dependency_bridge_v16[
            "accumulated_kiddo_family_packages"
        ]
        == 4
        and isamore_dependency_bridge_v16[
            "accumulated_kiddo_family_source_records"
        ]
        == 20
        and isamore_dependency_bridge_v16["prior_stop"] == "kiddo"
        and isamore_dependency_bridge_v16["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v16[
            "independent_source_compilation_passed"
        ]
        is True
        and isamore_dependency_bridge_v16["control_executed"] is False
        and isamore_dependency_bridge_v16[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v16 freeze changed",
    )
    require(
        iteration516["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration516["progress"][
            "isamore_kiddo_partial_family_packages_bridged"
        ]
        == 4
        and iteration516["progress"][
            "isamore_kiddo_partial_family_source_records"
        ]
        == 20
        and iteration516["progress"]["isamore_divrem_exact_source_compiled"]
        is True
        and iteration516["progress"]["isamore_kiddo_root_source_acquired"]
        is False
        and iteration516["progress"][
            "isamore_offline_build_stop_after_phase"
        ]
        == "kiddo"
        and iteration516["progress"]["isamore_control_executed"] is False
        and iteration516["authorization"]["prerequisites_passed"] == 5
        and iteration516["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration516["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.16 inflated verdict",
    )
    require(
        isamore_remaining_math_channels["status"]
        == "ISAMORE_REMAINING_MATH_CHANNELS_AUDITED_NO_EXACT_SOURCE"
        and len(isamore_remaining_math_channels["locked_identities"]) == 3
        and isamore_remaining_math_channels["rejected_substitution"][
            "accepted"
        ]
        is False
        and isamore_remaining_math_channels["checks"][
            "exact_local_source_bytes_present"
        ]
        is False
        and isamore_remaining_math_channels["checks"][
            "third_party_mirror_substituted"
        ]
        is False
        and isamore_remaining_math_channels["accumulated_kiddo_family"][
            "packages_bridged"
        ]
        == 4
        and isamore_remaining_math_channels["next_build_stop"]["package"]
        == "kiddo"
        and isamore_remaining_math_channels["control_executed"] is False
        and isamore_remaining_math_channels["validation_v6_accessed"] is False,
        "ISAMORE remaining-math channel boundary changed",
    )
    require(
        len(isamore_dependency_bridge_v17["records"]) == 3
        and isamore_dependency_bridge_v17["phases"] == [127]
        and isamore_dependency_bridge_v17["locked_packages_audited"] == 3
        and isamore_dependency_bridge_v17["packages_acquired"] == 0
        and isamore_dependency_bridge_v17[
            "third_party_mirror_substituted"
        ]
        is False
        and isamore_dependency_bridge_v17[
            "accumulated_kiddo_family_packages"
        ]
        == 4
        and isamore_dependency_bridge_v17["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v17["control_executed"] is False
        and isamore_dependency_bridge_v17[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v17 freeze changed",
    )
    require(
        iteration517["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration517["progress"][
            "isamore_remaining_math_channels_audited"
        ]
        == 3
        and iteration517["progress"][
            "isamore_remaining_math_exact_sources_acquired"
        ]
        == 0
        and iteration517["progress"][
            "isamore_third_party_math_mirror_substituted"
        ]
        is False
        and iteration517["progress"][
            "isamore_kiddo_partial_family_packages_bridged"
        ]
        == 4
        and iteration517["progress"]["isamore_control_executed"] is False
        and iteration517["authorization"]["prerequisites_passed"] == 5
        and iteration517["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration517["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.17 inflated verdict",
    )
    require(
        isamore_coin_cbc_bindings["status"]
        == "ISAMORE_COIN_CBC_RUST_BINDINGS_COMPILE_NATIVE_UNAVAILABLE"
        and isamore_coin_cbc_bindings["bridge"]["revision"]
        == "0edcbcea3a238909f296c9d78dbb3fae0190c0e9"
        and isamore_coin_cbc_bindings["bridge"]["record_count"] == 7
        and isamore_coin_cbc_bindings["bridge"]["byte_exact_local_records"]
        == 6
        and isamore_coin_cbc_bindings["bridge"]["exact_staged_records"] == 7
        and isamore_coin_cbc_bindings["checks"][
            "rust_binding_source_compilation_passed"
        ]
        is True
        and isamore_coin_cbc_bindings["checks"]["native_libcbc_available"]
        is False
        and isamore_coin_cbc_bindings["checks"]["pinned_nightly_available"]
        is False
        and isamore_coin_cbc_bindings["checks"][
            "link_or_solver_execution_attempted"
        ]
        is False
        and isamore_coin_cbc_bindings["next_build_stop"]["package"] == "kiddo"
        and isamore_coin_cbc_bindings["control_executed"] is False
        and isamore_coin_cbc_bindings["validation_v6_accessed"] is False,
        "ISAMORE Coin-CBC binding bridge changed",
    )
    require(
        len(isamore_dependency_bridge_v18["records"]) == 10
        and isamore_dependency_bridge_v18["phases"] == [128]
        and isamore_dependency_bridge_v18["bridged_packages"]
        == ["coin_cbc 0.1.8", "coin_cbc_sys 0.1.2"]
        and isamore_dependency_bridge_v18["source_records"] == 7
        and isamore_dependency_bridge_v18["exact_staged_records"] == 7
        and isamore_dependency_bridge_v18[
            "independent_source_compilation_passed"
        ]
        is True
        and isamore_dependency_bridge_v18["native_libcbc_available"] is False
        and isamore_dependency_bridge_v18["pinned_nightly_available"] is False
        and isamore_dependency_bridge_v18["solver_executed"] is False
        and isamore_dependency_bridge_v18["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v18["control_executed"] is False
        and isamore_dependency_bridge_v18[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v18 freeze changed",
    )
    require(
        iteration518["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration518["progress"][
            "isamore_coin_cbc_rust_binding_packages_bridged"
        ]
        == 2
        and iteration518["progress"][
            "isamore_coin_cbc_source_records_authenticated"
        ]
        == 7
        and iteration518["progress"][
            "isamore_coin_cbc_rust_binding_source_compiled"
        ]
        is True
        and iteration518["progress"]["isamore_native_libcbc_available"]
        is False
        and iteration518["progress"]["isamore_pinned_nightly_available"]
        is False
        and iteration518["progress"]["isamore_coin_cbc_solver_executed"]
        is False
        and iteration518["progress"]["isamore_control_executed"] is False
        and iteration518["authorization"]["prerequisites_passed"] == 5
        and iteration518["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration518["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.18 inflated verdict",
    )
    require(
        isamore_native_lp_acquisition["status"]
        == "ISAMORE_NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE"
        and isamore_native_lp_acquisition["apt_channels"][
            "candidate_version"
        ]
        == "2.10.11+ds1-2"
        and isamore_native_lp_acquisition["apt_channels"]["download_probe"][
            "downloaded_artifacts"
        ]
        == []
        and isamore_native_lp_acquisition["apt_channels"][
            "download_only_no_system_install"
        ]
        is True
        and isamore_native_lp_acquisition["toolchain_channel"][
            "local_toolchain_present"
        ]
        is False
        and isamore_native_lp_acquisition["toolchain_channel"][
            "network_install_attempted"
        ]
        is False
        and isamore_native_lp_acquisition["checks"][
            "system_libcbc_available"
        ]
        is False
        and isamore_native_lp_acquisition["checks"][
            "isamore_algorithm_execution_reached"
        ]
        is False
        and isamore_native_lp_acquisition["next_build_stop"]["package"]
        == "kiddo"
        and isamore_native_lp_acquisition["control_executed"] is False
        and isamore_native_lp_acquisition["validation_v6_accessed"] is False,
        "ISAMORE native LP acquisition boundary changed",
    )
    require(
        len(isamore_dependency_bridge_v19["records"]) == 3
        and isamore_dependency_bridge_v19["phases"] == [129]
        and isamore_dependency_bridge_v19["apt_candidate_version"]
        == "2.10.11+ds1-2"
        and isamore_dependency_bridge_v19["native_cbc_downloaded"] is False
        and isamore_dependency_bridge_v19["native_cbc_installed"] is False
        and isamore_dependency_bridge_v19["native_libcbc_available"] is False
        and isamore_dependency_bridge_v19["pinned_nightly_available"] is False
        and isamore_dependency_bridge_v19["link_attempted"] is False
        and isamore_dependency_bridge_v19["solver_executed"] is False
        and isamore_dependency_bridge_v19["next_stop"] == "kiddo"
        and isamore_dependency_bridge_v19["control_executed"] is False
        and isamore_dependency_bridge_v19[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE dependency-bridge-v19 freeze changed",
    )
    require(
        iteration519["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration519["progress"][
            "isamore_native_cbc_apt_candidate_identified"
        ]
        == "2.10.11+ds1-2"
        and iteration519["progress"]["isamore_native_cbc_downloaded"] is False
        and iteration519["progress"]["isamore_native_cbc_installed"] is False
        and iteration519["progress"]["isamore_native_libcbc_available"]
        is False
        and iteration519["progress"]["isamore_pinned_nightly_available"]
        is False
        and iteration519["progress"]["isamore_native_lp_link_attempted"]
        is False
        and iteration519["progress"]["isamore_control_executed"] is False
        and iteration519["authorization"]["prerequisites_passed"] == 5
        and iteration519["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration519["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.19 inflated verdict",
    )
    require(
        isamore_archive_transport["status"]
        == "ISAMORE_EXACT_ARCHIVE_TRANSPORT_STILL_UNAVAILABLE"
        and len(isamore_archive_transport["locked_packages"]) == 4
        and isamore_archive_transport["local_exact_archives"] == []
        and len(isamore_archive_transport["download_probes"]) == 4
        and all(
            row["lock_checksum_match"] is False
            for row in isamore_archive_transport["download_probes"]
        )
        and isamore_archive_transport["checks"][
            "substitute_source_accepted"
        ]
        is False
        and isamore_archive_transport["next_build_stop"]["package"] == "kiddo"
        and isamore_archive_transport["control_executed"] is False
        and isamore_archive_transport["validation_v6_accessed"] is False,
        "ISAMORE exact-archive transport boundary changed",
    )
    require(
        a1_reference_no_go["status"]
        == "A1_OPAQUE_REFERENCE_FALLBACK_FORMALLY_REJECTED"
        and a1_reference_no_go["checks"][
            "load_artifact_typechecks_reference_program"
        ]
        is True
        and a1_reference_no_go["checks"][
            "candidate_reference_plan_is_identity_transport"
        ]
        is True
        and a1_reference_no_go["checks"][
            "opaque_framework_call_rejected"
        ]
        is True
        and a1_reference_no_go["checks"][
            "opaque_fallback_can_promote_A1"
        ]
        is False
        and a1_reference_no_go["decision"]["A1_production_integrated"]
        is False
        and a1_reference_no_go["decision"]["production_integrated_arms"] == 6
        and a1_reference_no_go["validation_v6_accessed"] is False,
        "A1 reference-fallback no-go boundary changed",
    )
    require(
        len(foundry_remediation_v20["records"]) == 5
        and foundry_remediation_v20["phases"] == [130, 131]
        and foundry_remediation_v20["exact_archives_acquired"] == 0
        and foundry_remediation_v20["exact_archives_required"] == 4
        and foundry_remediation_v20["substitute_source_accepted"] is False
        and foundry_remediation_v20["A1_opaque_fallback_rejected"] is True
        and foundry_remediation_v20["A1_production_integrated"] is False
        and foundry_remediation_v20["production_integrated_arms"] == 6
        and foundry_remediation_v20["prospective_trial_authorized"] is False,
        "Foundry remediation-v20 freeze changed",
    )
    require(
        iteration520["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration520["progress"][
            "isamore_exact_archive_transport_probes"
        ]
        == 4
        and iteration520["progress"]["isamore_exact_archives_acquired"] == 0
        and iteration520["progress"]["isamore_substitute_source_accepted"]
        is False
        and iteration520["progress"]["A1_opaque_reference_fallback_rejected"]
        is True
        and iteration520["progress"]["A1_production_integrated"] is False
        and iteration520["authorization"]["prerequisites_passed"] == 5
        and iteration520["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration520["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.20 inflated verdict",
    )
    require(
        enumo_tensor_feasibility_prefreeze["experiment_name"]
        == "ENUMO_TENSOR_DOMAIN_FEASIBILITY"
        and enumo_tensor_feasibility_prefreeze[
            "frozen_before_runner_implementation_or_execution"
        ]
        is True
        and enumo_tensor_feasibility_prefreeze["is_frozen_boolean_A7"]
        is False
        and enumo_tensor_feasibility_prefreeze["may_promote_A7"] is False
        and enumo_tensor_feasibility_prefreeze[
            "may_increase_production_integrated_arm_count"
        ]
        is False
        and enumo_tensor_feasibility_prefreeze["validation_v6_accessed"]
        is False,
        "Enumo tensor feasibility prefreeze changed",
    )
    require(
        enumo_tensor_feasibility["status"]
        == "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
        and all(enumo_tensor_feasibility["checks"].values())
        and enumo_tensor_feasibility["observed"]["workload_counts"]
        == [38, 136]
        and enumo_tensor_feasibility["observed"]["stage_rule_counts"]
        == [11, 7]
        and len(enumo_tensor_feasibility["observed"]["learned_rules"]) == 18
        and enumo_tensor_feasibility[
            "independent_expanded_validation"
        ]["total_lane_checks"]
        == 1176
        and enumo_tensor_feasibility["hostile_parser_selftest"][
            "rejected_cases"
        ]
        == 9
        and enumo_tensor_feasibility["claim_boundary"][
            "A7_production_integrated"
        ]
        is False
        and enumo_tensor_feasibility["claim_boundary"][
            "production_integrated_arms"
        ]
        == 6
        and enumo_tensor_feasibility["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
        "Enumo tensor feasibility boundary changed",
    )
    require(
        enumo_tensor_feasibility_result["learned_rule_count"] == 18
        and enumo_tensor_feasibility_result["independent_lane_checks"] == 1176
        and enumo_tensor_feasibility_result["A7_production_integrated"]
        is False
        and enumo_tensor_feasibility_result["production_integrated_arms"] == 6,
        "Enumo tensor feasibility result freeze changed",
    )
    require(
        enumo_tensor_rule_reuse_prefreeze["held_out_expression_count"] == 3339
        and enumo_tensor_rule_reuse_prefreeze[
            "fixed_portfolio_rule_count"
        ]
        == 13
        and enumo_tensor_rule_reuse_prefreeze[
            "learned_strict_wins_required"
        ]
        == 1
        and enumo_tensor_rule_reuse_prefreeze["is_frozen_boolean_A7"]
        is False
        and enumo_tensor_rule_reuse_prefreeze["may_promote_A7"] is False
        and enumo_tensor_rule_reuse_prefreeze["validation_v6_accessed"]
        is False,
        "Enumo tensor rule-reuse prefreeze changed",
    )
    require(
        enumo_tensor_rule_reuse["status"]
        == "ENUMO_TENSOR_RULE_REUSE_DOES_NOT_BEAT_FIXED"
        and enumo_tensor_rule_reuse["operationally_valid"] is True
        and all(enumo_tensor_rule_reuse["checks"].values())
        and enumo_tensor_rule_reuse["protocol_acceptance"]["accepted"]
        is False
        and enumo_tensor_rule_reuse["observed"][
            "held_out_expression_count"
        ]
        == 3339
        and enumo_tensor_rule_reuse["observed"]["learned_strict_wins"] == 0
        and enumo_tensor_rule_reuse["observed"]["fixed_strict_wins"] == 736
        and enumo_tensor_rule_reuse["observed"]["atom_cost_ties"] == 2603
        and enumo_tensor_rule_reuse["observed"]["state_cap_hits"] == 0
        and enumo_tensor_rule_reuse["observed"]["semantic_failures"] == []
        and enumo_tensor_rule_reuse["claim_boundary"][
            "A7_production_integrated"
        ]
        is False
        and enumo_tensor_rule_reuse["claim_boundary"][
            "production_integrated_arms"
        ]
        == 6
        and enumo_tensor_rule_reuse["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
        "Enumo tensor rule-reuse valid negative changed",
    )
    require(
        enumo_tensor_rule_reuse_result["learned_strict_wins"] == 0
        and enumo_tensor_rule_reuse_result["fixed_strict_wins"] == 736
        and enumo_tensor_rule_reuse_result["atom_cost_ties"] == 2603
        and enumo_tensor_rule_reuse_result["operationally_valid"] is True
        and enumo_tensor_rule_reuse_result["protocol_accepted"] is False
        and enumo_tensor_rule_reuse_result["production_integrated_arms"] == 6,
        "Enumo tensor rule-reuse result freeze changed",
    )
    require(
        iteration521["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration521["progress"][
            "enumo_tensor_domain_feasibility_established"
        ]
        is True
        and iteration521["progress"]["enumo_tensor_learned_rules"] == 18
        and iteration521["progress"][
            "enumo_tensor_reuse_held_out_expressions"
        ]
        == 3339
        and iteration521["progress"][
            "enumo_tensor_reuse_learned_strict_wins"
        ]
        == 0
        and iteration521["progress"]["enumo_tensor_reuse_fixed_strict_wins"]
        == 736
        and iteration521["progress"]["enumo_tensor_reuse_beats_fixed"]
        is False
        and iteration521["progress"]["A7_production_integrated"] is False
        and iteration521["authorization"]["prerequisites_passed"] == 5
        and iteration521["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration521["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.21 inflated verdict",
    )
    require(
        pareto_v08_search_distinction_prefreeze[
            "frozen_before_heldout_execution"
        ]
        is True
        and pareto_v08_search_distinction_prefreeze["candidate_tools"] == 4
        and pareto_v08_search_distinction_prefreeze[
            "runtime_inventions_admitted"
        ]
        == 0
        and pareto_v08_search_distinction_prefreeze[
            "stock_decomposition_duplicates"
        ]
        == 4
        and pareto_v08_search_distinction_prefreeze["primary_comparators"]
        == ["A3", "A9"]
        and pareto_v08_search_distinction_prefreeze["artifacts"] == 4
        and pareto_v08_search_distinction_prefreeze[
            "invocations_per_artifact"
        ]
        == 3
        and pareto_v08_search_distinction_prefreeze[
            "point_estimate_minimum"
        ]
        == 0.05
        and pareto_v08_search_distinction_prefreeze[
            "bootstrap_resamples"
        ]
        == 10000
        and pareto_v08_search_distinction_prefreeze[
            "required_raw_receipt_fields"
        ]
        == 22
        and pareto_v08_search_distinction_prefreeze[
            "terminal_native_dedup_stop_reclassified"
        ]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and pareto_v08_search_distinction_prefreeze[
            "V08_measurement_passed"
        ]
        is False
        and pareto_v08_search_distinction_prefreeze[
            "runtime_novelty_claimed"
        ]
        is False
        and pareto_v08_search_distinction_prefreeze[
            "validation_v6_accessed"
        ]
        is False
        and pareto_v08_search_distinction_prefreeze[
            "prospective_trial_authorized"
        ]
        is False,
        "V08 search-distinction prefreeze changed",
    )
    require(
        pareto_v08_search_distinction["status"]
        == "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        and all(pareto_v08_search_distinction["checks"].values())
        and all(
            pareto_v08_search_distinction["worker"]["checks"].values()
        )
        and pareto_v08_search_distinction["worker"]["hostile_selftest"][
            "hostile_cases"
        ]
        == 15
        and pareto_v08_search_distinction["worker"]["hostile_selftest"][
            "rejected_cases"
        ]
        == 15
        and pareto_v08_search_distinction["worker"][
            "synthetic_positive_control"
        ]["bootstrap_resamples"]
        == 10000
        and pareto_v08_search_distinction["preflight_effect"][
            "duplicate_grammar_phase_required"
        ]
        is False
        and pareto_v08_search_distinction["preflight_effect"][
            "native_duplicate_fact_preserved"
        ]
        is True
        and pareto_v08_search_distinction["preflight_effect"][
            "terminal_native_dedup_stop"
        ]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and pareto_v08_search_distinction["preflight_effect"][
            "V08_measurement_passed"
        ]
        is False
        and pareto_v08_search_distinction["preflight_effect"]["P1_advanced"]
        is False
        and pareto_v08_search_distinction["preflight_effect"][
            "production_integrated_arms"
        ]
        == 6
        and pareto_v08_search_distinction["preflight_effect"][
            "validation_v6_accessed"
        ]
        is False
        and pareto_v08_search_distinction["preflight_effect"][
            "prospective_trial_authorized"
        ]
        is False,
        "V08 search-distinction conformance boundary changed",
    )
    require(
        pareto_v08_search_distinction_result[
            "required_raw_receipt_fields"
        ]
        == 22
        and pareto_v08_search_distinction_result[
            "hostile_ledgers_rejected"
        ]
        == 15
        and pareto_v08_search_distinction_result["bootstrap_resamples"]
        == 10000
        and pareto_v08_search_distinction_result[
            "terminal_native_dedup_stop"
        ]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and pareto_v08_search_distinction_result[
            "V08_measurement_passed"
        ]
        is False
        and pareto_v08_search_distinction_result[
            "native_duplicate_fact_preserved"
        ]
        is True
        and pareto_v08_search_distinction_result[
            "duplicate_grammar_phase_required"
        ]
        is False
        and pareto_v08_search_distinction_result["P1_advanced"] is False
        and pareto_v08_search_distinction_result[
            "production_integrated_arms"
        ]
        == 6
        and pareto_v08_search_distinction_result["validation_v6_accessed"]
        is False
        and pareto_v08_search_distinction_result[
            "prospective_trial_authorized"
        ]
        is False,
        "V08 search-distinction result freeze changed",
    )
    require(
        iteration522["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration522["progress"][
            "autonomous_typed_grammar_already_established"
        ]
        is True
        and iteration522["progress"]["duplicate_grammar_phase_required"]
        is False
        and iteration522["progress"]["candidate_calibration_unique_nodes"]
        == 53
        and iteration522["progress"]["fixed_calibration_unique_nodes"] == 51
        and iteration522["progress"]["candidate_runtime_inventions_admitted"]
        == 0
        and iteration522["progress"][
            "candidate_stock_decomposition_duplicates"
        ]
        == 4
        and iteration522["progress"]["V08_search_receipt_fields_frozen"]
        == 22
        and iteration522["progress"]["V08_hostile_ledgers_rejected"] == 15
        and iteration522["progress"][
            "V08_terminal_native_dedup_stop_reclassified"
        ]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and iteration522["progress"]["V08_measurement_passed"] is False
        and iteration522["authorization"]["prerequisites_passed"] == 5
        and iteration522["authorization"]["active_stop_conditions"] == 0
        and iteration522["authorization"][
            "pending_trial_validity_measurements"
        ]
        == 1
        and iteration522["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration522["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.22 inflated verdict",
    )
    require(
        eggmind_reproduction_sufficiency["status"]
        == "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
        and all(eggmind_reproduction_sufficiency["checks"].values())
        and eggmind_reproduction_sufficiency["surface_counts"]
        == {"specified": 10, "missing_outcome_determining": 16}
        and eggmind_reproduction_sufficiency["decisions"][
            "source_faithful_EggMind_build_authorized"
        ]
        is False
        and eggmind_reproduction_sufficiency["decisions"][
            "deterministic_llm_free_substitute_may_be_called_EggMind"
        ]
        is False
        and eggmind_reproduction_sufficiency["decisions"][
            "A8_production_integrated"
        ]
        is False
        and eggmind_reproduction_sufficiency["decisions"]["P1_complete"]
        is False
        and eggmind_reproduction_sufficiency["validation_v6_accessed"]
        is False,
        "EggMind full-reproduction sufficiency boundary changed",
    )
    require(
        eggmind_reproduction_sufficiency_result["specified_surfaces"] == 10
        and eggmind_reproduction_sufficiency_result[
            "missing_outcome_determining_surfaces"
        ]
        == 16
        and eggmind_reproduction_sufficiency_result[
            "A8_production_integrated"
        ]
        is False
        and eggmind_reproduction_sufficiency_result["P1_complete"] is False
        and eggmind_reproduction_sufficiency_result[
            "prospective_trial_authorized"
        ]
        is False,
        "EggMind reproduction sufficiency result freeze changed",
    )
    require(
        isamore_exact_artifact_ingress["status"]
        == "ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_PASS"
        and all(isamore_exact_artifact_ingress["checks"].values())
        and isamore_exact_artifact_ingress["locked_registry_identities"]
        == 310
        and len(isamore_exact_artifact_ingress["hostile_rejections"]) == 11
        and all(
            row["rejected"]
            for row in isamore_exact_artifact_ingress[
                "hostile_rejections"
            ]
        )
        and isamore_exact_artifact_ingress["real_inbox"][
            "exact_artifacts_acquired"
        ]
        == 0
        and isamore_exact_artifact_ingress["P1_complete"] is False
        and isamore_exact_artifact_ingress["validation_v6_accessed"]
        is False,
        "ISAMORE exact-artifact ingress boundary changed",
    )
    require(
        isamore_exact_artifact_ingress_result[
            "locked_registry_identities"
        ]
        == 310
        and isamore_exact_artifact_ingress_result[
            "hostile_rejections"
        ]
        == 11
        and isamore_exact_artifact_ingress_result[
            "real_exact_artifacts_acquired"
        ]
        == 0
        and isamore_exact_artifact_ingress_result["P1_complete"] is False
        and isamore_exact_artifact_ingress_result[
            "prospective_trial_authorized"
        ]
        is False,
        "ISAMORE exact-artifact ingress result freeze changed",
    )
    require(
        iteration523["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration523["progress"]["A8_paper_specified_surfaces"] == 10
        and iteration523["progress"][
            "A8_missing_outcome_determining_surfaces"
        ]
        == 16
        and iteration523["progress"][
            "A8_paper_only_full_reproduction_specified"
        ]
        is False
        and iteration523["progress"][
            "isamore_exact_ingress_locked_identities"
        ]
        == 310
        and iteration523["progress"][
            "isamore_exact_ingress_hostile_rejections"
        ]
        == 11
        and iteration523["progress"][
            "isamore_exact_ingress_real_artifacts_acquired"
        ]
        == 0
        and iteration523["authorization"]["prerequisites_passed"] == 5
        and iteration523["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration523["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.23 inflated verdict",
    )
    require(
        sympy_cse_control_prefreeze["frozen_before_control_execution"]
        is True
        and sympy_cse_control_prefreeze["distribution_version"] == "1.13.1"
        and sympy_cse_control_prefreeze["minimum_collected"] == 60
        and sympy_cse_control_prefreeze["minimum_passed"] == 55
        and sympy_cse_control_prefreeze["hostile_checks"] == 10
        and sympy_cse_control_prefreeze["may_replace_isamore_as_A6"]
        is False
        and sympy_cse_control_prefreeze[
            "may_increase_production_integrated_arm_count"
        ]
        is False
        and sympy_cse_control_prefreeze["validation_v6_accessed"] is False,
        "SymPy CSE pre-execution freeze changed",
    )
    require(
        sympy_cse_execution_amendment["ordinary_passes_required"] == 53
        and sympy_cse_execution_amendment[
            "source_declared_xfails_required"
        ]
        == 8
        and sympy_cse_execution_amendment[
            "minimum_accepted_expected_outcomes"
        ]
        == 55
        and sympy_cse_execution_amendment["pristine_preregistration"]
        is False
        and sympy_cse_execution_amendment[
            "initial_infrastructure_failure_preserved"
        ]
        is True
        and sympy_cse_execution_amendment["validation_v6_accessed"] is False,
        "SymPy CSE execution amendment changed",
    )
    require(
        sympy_cse_source_control["status"]
        == "SYMPY_CSE_SOURCE_CONTROL_PRELIMINARY_PASS"
        and all(sympy_cse_source_control["gates"].values())
        and sympy_cse_source_control["official_suite"]["tests"] == 61
        and sympy_cse_source_control["official_suite"]["passed"] == 53
        and sympy_cse_source_control["official_suite"][
            "source_declared_xfails"
        ]
        == 8
        and sympy_cse_source_control["official_suite"][
            "pytest_classified_xfails"
        ]
        == 8
        and sympy_cse_source_control["official_suite"]["failures"] == 0
        and sympy_cse_source_control["official_suite"]["errors"] == 0
        and sympy_cse_source_control["official_suite"]["xpassed"] == 0
        and sympy_cse_source_control["distribution_integrity"][
            "hashed_files_verified"
        ]
        == 1556
        and sympy_cse_source_control["initial_infrastructure_failure"][
            "preserved"
        ]
        is True
        and sympy_cse_source_control["P1_complete"] is False
        and sympy_cse_source_control["validation_v6_accessed"] is False,
        "SymPy CSE source-control boundary changed",
    )
    require(
        sympy_cse_conformance["status"]
        == "SYMPY_CSE_FOURTH_SOURCE_FAITHFUL_CONTROL_PASS"
        and all(sympy_cse_conformance["checks"].values())
        and sympy_cse_conformance["independent_result"]["baseline"][
            "comparisons"
        ]
        == 15
        and sympy_cse_conformance["independent_result"][
            "renamed_reordered"
        ]["comparisons"]
        == 15
        and sympy_cse_conformance["independent_result"]["baseline"][
            "maximum_absolute_error"
        ]
        == 0.0
        and len(sympy_cse_conformance["hostile_rejections"]) == 10
        and all(
            row["rejected"]
            for row in sympy_cse_conformance["hostile_rejections"]
        )
        and sympy_cse_conformance["P1"]["complete"] is True
        and sympy_cse_conformance["P1"][
            "source_faithful_controls_reproduced"
        ]
        == 4
        and sympy_cse_conformance["A6_satisfied"] is False
        and sympy_cse_conformance["A8_satisfied"] is False
        and sympy_cse_conformance["production_integrated_arms"] == 6
        and sympy_cse_conformance["validation_v6_accessed"] is False,
        "SymPy CSE independent/resource conformance changed",
    )
    require(
        sympy_cse_control_result["official_expected_outcomes"] == 61
        and sympy_cse_control_result[
            "distribution_hashed_files_verified"
        ]
        == 1556
        and sympy_cse_control_result[
            "independent_numeric_comparisons"
        ]
        == 30
        and sympy_cse_control_result["hostile_rejections"] == 10
        and sympy_cse_control_result[
            "source_faithful_controls_reproduced"
        ]
        == 4
        and sympy_cse_control_result["P1_complete"] is True
        and sympy_cse_control_result["A6_satisfied"] is False
        and sympy_cse_control_result["A8_satisfied"] is False
        and sympy_cse_control_result["production_integrated_arms"] == 6
        and sympy_cse_control_result["pristine_preregistration"] is False
        and sympy_cse_control_result["validation_v6_accessed"] is False,
        "SymPy CSE result freeze changed",
    )
    require(
        iteration524["verdict"] == "FOUNDRY_V6_NOT_READY"
        and iteration524["prerequisites"][
            "P1_external_control_conformance"
        ]
        is True
        and all(iteration524["prerequisites"].values())
        and iteration524["progress"][
            "source_faithful_controls_reproduced"
        ]
        == 4
        and iteration524["progress"][
            "sympy_cse_official_expected_outcomes"
        ]
        == 61
        and iteration524["progress"][
            "sympy_cse_independent_numeric_comparisons"
        ]
        == 30
        and iteration524["progress"]["sympy_cse_hostile_rejections"]
        == 10
        and iteration524["progress"][
            "sympy_cse_pristine_preregistration"
        ]
        is False
        and iteration524["authorization"]["prerequisites_passed"] == 6
        and iteration524["authorization"][
            "required_arms_production_integrated"
        ]
        == 6
        and iteration524["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.24 inflated verdict",
    )
    require(
        missing_arm_closure["status"]
        == "A7_REAL_GRAPH_TRANSFER_SELECTED_AS_NEXT_FALSIFICATION"
        and all(missing_arm_closure["checks"].values())
        and missing_arm_closure["selection"]["arm_id"] == "A7"
        and missing_arm_closure["selection"]["promotion_by_this_audit"] is False
        and missing_arm_closure["selection"][
            "production_integrated_arms_after_audit"
        ]
        == 6
        and missing_arm_closure["claim_boundary"]["validation_v6_accessed"]
        is False,
        "missing-arm closure ranking changed",
    )
    require(
        a7_real_transfer["status"] == "A7_ENUMO_REAL_GRAPH_TRANSFER_PASS"
        and all(a7_real_transfer["checks"].values())
        and a7_real_transfer["observed"]["summary"]["graphs"] == 23
        and a7_real_transfer["observed"]["summary"]["eligible_graphs"] == 17
        and a7_real_transfer["observed"]["summary"]["eligible_calls"] == 53
        and a7_real_transfer["observed"]["summary"][
            "learned_root_matches"
        ]
        == 282
        and a7_real_transfer["observed"]["summary"][
            "learned_selected_rewrites"
        ]
        == 24
        and a7_real_transfer["observed"]["summary"][
            "learned_concrete_receipts"
        ]
        == 72
        and a7_real_transfer["observed"]["summary"]["maximum_abs_error"] == 0.0
        and a7_real_transfer["decision"]["A7_production_integrated"] is False
        and a7_real_transfer["claim_boundary"]["validation_v6_accessed"]
        is False,
        "A7 real-graph transfer changed",
    )
    a7_summary = a7_runtime_mount["runtime_receipt"]["summary"]
    require(
        a7_runtime_mount["status"] == "A7_ENUMO_RUNTIME_CONFORMANCE_PASS"
        and all(a7_runtime_mount["checks"].values())
        and a7_summary["graphs"] == 23
        and a7_summary["unique_operator_targets"] == 41
        and a7_summary["call_function_invocations"] == 337
        and a7_summary["eligible_calls"] == 53
        and a7_summary["learned_root_matches"] == 282
        and a7_summary["raw_selected_rule_applications"] == 24
        and a7_summary["unique_selected_transformations"] == 12
        and a7_summary["whole_graph_executions"] == 69
        and a7_summary["unique_rewrite_concrete_checks"] == 36
        and a7_summary["maximum_absolute_error"] == 0.0
        and a7_runtime_mount["integration"]["A7_production_integrated"]
        is False
        and a7_runtime_mount["validation_v6_accessed"] is False,
        "A7 runtime mount changed",
    )
    require(
        a7_runtime_resource["status"]
        == "A7_ENUMO_RUNTIME_RESOURCE_COMPONENT_PASS"
        and all(a7_runtime_resource["checks"].values())
        and a7_runtime_resource["integration"]["A7_production_integrated"]
        is False
        and a7_runtime_resource["validation_v6_accessed"] is False,
        "A7 runtime resource audit changed",
    )
    require(
        a7_batch["status"] == "A7_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(a7_batch["checks"].values())
        and len(a7_batch["hostile_rejections"]) == 22
        and all(
            row["rejected_twice"] for row in a7_batch["hostile_rejections"]
        )
        and a7_batch["primary"]["artifacts"] == 23
        and a7_batch["primary"]["raw_selected_rule_uses"] == 24
        and a7_batch["primary"]["unique_selected_transformations"] == 12
        and a7_batch["independent"]["artifacts"] == 23
        and a7_batch["integration"]["production_integrated_arms"] == 7
        and a7_batch["validation_v6_accessed"] is False,
        "A7 shared batch conformance changed",
    )
    require(
        a7_batch_resource["status"]
        == "A7_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(a7_batch_resource["checks"].values())
        and a7_batch_resource["integration"]["A7_production_integrated"]
        is True
        and a7_batch_resource["integration"][
            "production_integrated_arms"
        ]
        == 7
        and a7_batch_resource["validation_v6_accessed"] is False,
        "A7 shared batch resource audit changed",
    )
    require(
        iteration525["verdict"] == "FOUNDRY_V6_NOT_READY"
        and all(iteration525["prerequisites"].values())
        and iteration525["progress"]["A7_production_integrated"] is True
        and iteration525["progress"]["A7_real_graph_eligible_calls"] == 53
        and iteration525["progress"][
            "A7_unique_selected_transformations"
        ]
        == 12
        and iteration525["progress"]["A7_strict_atom_cost_reductions"] == 0
        and iteration525["progress"]["A7_fixed_portfolio_beaten"] is False
        and iteration525["authorization"]["prerequisites_passed"] == 6
        and iteration525["authorization"][
            "required_arms_production_integrated"
        ]
        == 7
        and iteration525["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.25 inflated verdict",
    )
    a1_reachability_summary = a1_subgraph_reachability["observed"][
        "summary"
    ]
    require(
        a1_subgraph_reachability["status"]
        == "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_POSITIVE"
        and all(a1_subgraph_reachability["checks"].values())
        and a1_subgraph_reachability["operationally_valid"] is True
        and a1_reachability_summary["graphs"] == 23
        and a1_reachability_summary["unique_targets"] == 41
        and a1_reachability_summary["calls"] == 337
        and a1_reachability_summary["connected_subsets_2_to_6"] == 7093
        and a1_reachability_summary["histogram_candidates"] == 6
        and a1_reachability_summary["semantic_candidates"] == 6
        and a1_reachability_summary["semantic_candidate_artifacts"] == 3
        and a1_reachability_summary["semantic_candidate_families"]
        == ["dense_matrix_chain", "fold_conv_batch_norm"]
        and a1_subgraph_reachability["decision"]["full_lowering_justified"]
        is True
        and a1_subgraph_reachability["decision"]["A1_production_integrated"]
        is False
        and a1_subgraph_reachability["claim_boundary"][
            "typed_lowering_implemented"
        ]
        is False
        and a1_subgraph_reachability["claim_boundary"][
            "constructor_executed"
        ]
        is False
        and a1_subgraph_reachability["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
        "A1 subgraph constructor reachability changed",
    )
    require(
        iteration526["verdict"] == "FOUNDRY_V6_NOT_READY"
        and all(iteration526["prerequisites"].values())
        and iteration526["progress"]["A1_connected_subgraphs_enumerated"]
        == 7093
        and iteration526["progress"]["A1_semantic_constructor_candidates"]
        == 6
        and iteration526["progress"]["A1_pattern_first_lowering_justified"]
        is True
        and iteration526["progress"]["A1_typed_lowering_implemented"] is False
        and iteration526["progress"]["A1_constructor_executed"] is False
        and iteration526["progress"]["A1_production_integrated"] is False
        and iteration526["authorization"][
            "required_arms_production_integrated"
        ]
        == 7
        and iteration526["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.26 inflated verdict",
    )
    a1_corrected_summary = a1_subgraph_reachability_corrected["observed"][
        "summary"
    ]
    require(
        a1_subgraph_reachability_corrected["status"]
        == "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_POSITIVE"
        and all(a1_subgraph_reachability_corrected["checks"].values())
        and a1_subgraph_reachability_corrected["operationally_valid"] is True
        and a1_subgraph_reachability_corrected["pristine_preregistration"]
        is False
        and a1_corrected_summary["connected_subsets_2_to_6"] == 7093
        and a1_corrected_summary["histogram_candidates"] == 6
        and a1_corrected_summary["direction_rejected_dense_candidates"] == 3
        and a1_corrected_summary["semantic_candidates"] == 3
        and a1_corrected_summary["semantic_candidate_artifacts"] == 1
        and a1_corrected_summary["semantic_candidate_families"]
        == ["fold_conv_batch_norm"]
        and len(
            a1_subgraph_reachability_corrected["observed"][
                "direction_rejected_candidates"
            ]
        )
        == 3
        and a1_subgraph_reachability_corrected["decision"][
            "A1_production_integrated"
        ]
        is False
        and a1_subgraph_reachability_corrected["claim_boundary"][
            "initial_false_positive_preserved"
        ]
        is True
        and a1_subgraph_reachability_corrected["claim_boundary"][
            "constructor_executed"
        ]
        is False
        and a1_subgraph_reachability_corrected["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
        "corrected A1 subgraph reachability changed",
    )
    require(
        iteration527["verdict"] == "FOUNDRY_V6_NOT_READY"
        and all(iteration527["prerequisites"].values())
        and iteration527["progress"][
            "A1_initial_dense_false_positives_preserved"
        ]
        == 3
        and iteration527["progress"][
            "A1_direction_rejected_dense_candidates"
        ]
        == 3
        and iteration527["progress"]["A1_semantic_constructor_candidates"]
        == 3
        and iteration527["progress"]["A1_semantic_candidate_families"]
        == ["fold_conv_batch_norm"]
        and iteration527["progress"][
            "A1_direction_amendment_pristine_preregistration"
        ]
        is False
        and iteration527["progress"]["A1_typed_lowering_implemented"] is False
        and iteration527["progress"]["A1_constructor_executed"] is False
        and iteration527["authorization"][
            "required_arms_production_integrated"
        ]
        == 7
        and iteration527["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.27 inflated verdict",
    )
    require(
        a1_fold_failed_conformance["status"]
        == "A1_ADAPTED_FOLD_CONFORMANCE_INVALID"
        and a1_fold_failed_conformance["operationally_valid"] is False
        and a1_fold_failed_conformance["checks"][
            "protocol_freeze_and_providers_exact"
        ]
        is True
        and a1_fold_failed_conformance["receipt"]["returncode"] == 1
        and "v5 nonreference plan exceeded tolerance"
        in a1_fold_failed_conformance["receipt"]["stderr_text"]
        and a1_fold_failed_conformance["decision"][
            "A1_production_integrated"
        ]
        is False
        and a1_fold_failed_conformance["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
        "A1 failed absolute-only conformance history changed",
    )
    a1_numeric_summary = a1_numerical_remediation["observed"]["summary"]
    require(
        a1_numerical_remediation["status"]
        == "A1_POST_FAILURE_NUMERICAL_REMEDIATION_PASS"
        and all(a1_numerical_remediation["checks"].values())
        and a1_numerical_remediation["operationally_valid"] is True
        and a1_numerical_remediation["pristine_preregistration"] is False
        and a1_numerical_remediation["decision"][
            "phase146_remains_failed"
        ]
        is True
        and a1_numeric_summary["real_source_comparisons"] == 9
        and a1_numeric_summary["unseen_panel_replicates"] == 48
        and a1_numeric_summary["unseen_panel_combined_passes"] == 48
        and a1_numeric_summary["unseen_panel_byte_identical_lowerings"]
        == 48
        and a1_numeric_summary["unseen_panel_plan_sets_agree"] == 48
        and a1_numeric_summary["hostile_rejections"] == 12
        and a1_numeric_summary["maximum_panel_excess"] == 0.0
        and a1_numerical_remediation["claim_boundary"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "A1 post-failure numerical remediation changed",
    )
    a1_runtime_summary = a1_full_runtime_contract["mount"]["summary"]
    require(
        a1_full_runtime_contract["status"]
        == "A1_FULL_RUNTIME_CONTRACT_BATCH_PASS"
        and all(a1_full_runtime_contract["checks"].values())
        and a1_full_runtime_contract["operationally_valid"] is True
        and a1_runtime_summary["graphs"] == 23
        and a1_runtime_summary["unique_operator_targets"] == 41
        and a1_runtime_summary["call_function_invocations"] == 337
        and a1_runtime_summary["eligible_graphs"] == 1
        and a1_runtime_summary["eligible_fold_sites"] == 3
        and a1_runtime_summary["whole_graph_executions"] == 69
        and a1_runtime_summary["fold_checks"] == 9
        and a1_runtime_summary["tool_direct_uses"] == 3
        and a1_runtime_summary["maximum_absolute_error"] <= 1.0e-5
        and len(a1_full_runtime_contract["contract_bindings"]) == 23
        and len(a1_full_runtime_contract["hostile_rejections"]) == 22
        and all(
            row["rejected_by_primary_and_independent"]
            for row in a1_full_runtime_contract["hostile_rejections"]
        )
        and a1_full_runtime_contract["aggregate_accounting"][
            "primary_accepts"
        ]
        == 23
        and a1_full_runtime_contract["aggregate_accounting"][
            "independent_accepts"
        ]
        == 23
        and a1_full_runtime_contract["aggregate_accounting"][
            "resource_multiplier_applied"
        ]
        == 1
        and a1_full_runtime_contract["integration"][
            "production_integrated_arms"
        ]
        == 8
        and a1_full_runtime_contract["integration"][
            "phase146_remains_failed"
        ]
        is True
        and a1_full_runtime_contract["validation_v6_accessed"] is False,
        "A1 full runtime contract batch changed",
    )
    require(
        iteration528["verdict"] == "FOUNDRY_V6_NOT_READY"
        and all(iteration528["prerequisites"].values())
        and iteration528["progress"]["production_integrated_arms"] == 8
        and iteration528["progress"]["A1_production_integrated"] is True
        and iteration528["progress"]["A1_constructor_executed"] is True
        and iteration528["progress"][
            "A1_phase146_absolute_only_conformance_failed"
        ]
        is True
        and iteration528["progress"][
            "A1_post_failure_amendment_pristine_preregistration"
        ]
        is False
        and iteration528["progress"]["A1_unseen_numerical_panel_passes"]
        == 48
        and iteration528["progress"]["A1_contract_pairs"] == 23
        and iteration528["authorization"][
            "required_arms_production_integrated"
        ]
        == 8
        and iteration528["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.28 inflated verdict",
    )
    a6_reach_summary = a6_reachability["observed"]["summary"]
    a6_runtime_summary = a6_runtime_contract["mount"]["summary"]
    require(
        a6_reachability["status"]
        == "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_POSITIVE"
        and all(a6_reachability["checks"].values())
        and a6_reach_summary["roots"] == 337
        and a6_reach_summary["unordered_root_pairs"] == 56616
        and a6_reach_summary["contract_candidates"] == 21
        and a6_reach_summary["selected_matches"] == 12
        and a6_reach_summary["selected_matching_artifacts"] == 10
        and a6_reachability["decision"]["A6_production_integrated"] is False
        and a6_reachability["claim_boundary"]["not_production_integration"]
        is True,
        "A6 reachability result changed",
    )
    require(
        a6_runtime_contract["status"]
        == "A6_TYPED_ANTI_UNIFICATION_RUNTIME_CONTRACT_PASS"
        and a6_runtime_contract["operationally_valid"] is True
        and all(a6_runtime_contract["checks"].values())
        and a6_runtime_summary["graphs"] == 23
        and a6_runtime_summary["eligible_graphs"] == 10
        and a6_runtime_summary["eligible_tool_sites"] == 12
        and a6_runtime_summary["whole_graph_executions"] == 69
        and a6_runtime_summary["tool_direct_uses"] == 36
        and a6_runtime_summary["maximum_absolute_error"] == 0.0
        and len(a6_runtime_contract["contract_bindings"]) == 23
        and len(a6_runtime_contract["hostile_rejections"]) == 22
        and a6_runtime_contract["integration"]["production_integrated_arms"]
        == 9,
        "A6 runtime contract changed",
    )
    require(
        iteration529["verdict"] == "FOUNDRY_V6_NOT_READY"
        and all(iteration529["prerequisites"].values())
        and iteration529["progress"]["production_integrated_arms"] == 9
        and iteration529["progress"]["A6_production_integrated"] is True
        and iteration529["progress"][
            "A6_selected_pattern_is_fixed_linear_relu_duplicate"
        ]
        is True
        and iteration529["authorization"][
            "required_arms_production_integrated"
        ]
        == 9
        and iteration529["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.29 inflated verdict",
    )
    a8_reach_summary = a8_reachability["observed"]["summary"]
    a8_runtime_summary = a8_runtime_contract["mount"]["summary"]
    require(
        a8_reachability["status"]
        == "A8_ADAPTED_STRATEGY_REACHABILITY_POSITIVE"
        and a8_reachability["operationally_valid"] is True
        and all(a8_reachability["checks"].values())
        and a8_reach_summary["candidate_strategies"] == 40320
        and a8_reach_summary["baseline_direct_uses"] == 22
        and a8_reach_summary["selected_direct_uses"] == 20
        and a8_reach_summary["selected_covered_nodes"] == 49
        and a8_reachability["observed"]["pristine_preregistration"] is False
        and a8_reachability["decision"]["A8_production_integrated"] is False,
        "A8 reachability result changed",
    )
    require(
        a8_runtime_contract["status"]
        == "A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_PASS"
        and a8_runtime_contract["operationally_valid"] is True
        and all(a8_runtime_contract["checks"].values())
        and a8_runtime_summary["graphs"] == 23
        and a8_runtime_summary["eligible_graphs"] == 12
        and a8_runtime_summary["eligible_strategy_applications"] == 20
        and a8_runtime_summary["covered_graph_nodes"] == 49
        and a8_runtime_summary["whole_graph_executions"] == 69
        and a8_runtime_summary["strategy_tool_direct_uses"] == 60
        and a8_runtime_summary["maximum_absolute_error"] == 0.0
        and len(a8_runtime_contract["contract_bindings"]) == 23
        and len(a8_runtime_contract["hostile_rejections"]) == 22
        and a8_runtime_contract["integration"]["production_integrated_arms"]
        == 10,
        "A8 runtime contract changed",
    )
    require(
        v6_access_incident["status"]
        == "VALIDATION_V6_PROSPECTIVE_CHRONOLOGY_INVALIDATED"
        and v6_access_incident["production_integration"][
            "calibration_integration_remains_valid"
        ]
        is True
        and v6_access_incident["access"]["runtime_module_imported"] is False
        and v6_access_incident["access"]["workloads_instantiated"] is False
        and v6_access_incident["access"]["outcomes_observed"] is False
        and v6_access_incident["effects"][
            "validation_v6_may_be_used_for_prospective_claim"
        ]
        is False
        and v6_access_incident["effects"]["V08_measurement_passed"] is False
        and v6_access_incident["effects"]["prospective_trial_executed"]
        is False,
        "validation-v6 access incident changed",
    )
    require(
        iteration530["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration530["prerequisites"].values()) == 5
        and iteration530["prerequisites"][
            "P6_unchanged_prospective_freeze"
        ]
        is False
        and iteration530["progress"]["production_integrated_arms"] == 10
        and iteration530["progress"]["A8_production_integrated"] is True
        and iteration530["progress"][
            "validation_v6_retired_from_primary_prospective_claim"
        ]
        is True
        and iteration530["authorization"][
            "required_arms_production_integrated"
        ]
        == 10
        and iteration530["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.30 fail-closed verdict changed",
    )
    v7_intake_summary = validation_v7_intake["observed"]["summary"]
    require(
        validation_v7_intake["status"]
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING"
        and validation_v7_intake["operationally_valid"] is True
        and all(validation_v7_intake["checks"].values())
        and v7_intake_summary["positive_validators"] == 2
        and v7_intake_summary["hostile_cases"] == 16
        and v7_intake_summary["hostile_rejected_twice"] == 16
        and v7_intake_summary["real_present_required_files"] == 0
        and v7_intake_summary["real_missing_required_files"] == 5
        and validation_v7_intake["observed"]["payload_decrypted"] is False
        and validation_v7_intake["observed"][
            "source_runtime_graph_shape_or_outcome_accessed"
        ]
        is False
        and validation_v7_intake["claim_boundary"]["P2_not_advanced"] is True
        and validation_v7_intake["claim_boundary"]["P6_not_advanced"] is True
        and validation_v7_intake["decision"]["P2_advanced"] is False
        and validation_v7_intake["decision"]["P6_advanced"] is False
        and validation_v7_intake["decision"][
            "prospective_trial_authorized"
        ]
        is False
        and validation_v7_intake["claim_boundary"][
            "prospective_trial_executed"
        ]
        is False,
        "validation-v7 identity-only intake result changed",
    )
    require(
        iteration531["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration531["prerequisites"].values()) == 5
        and iteration531["prerequisites"][
            "P6_unchanged_prospective_freeze"
        ]
        is False
        and iteration531["progress"]["P6_complete"] is False
        and iteration531["progress"]["production_integrated_arms"] == 10
        and iteration531["progress"][
            "validation_v7_identity_only_protocol_frozen"
        ]
        is True
        and iteration531["progress"]["validation_v7_intake_complete"] is False
        and iteration531["progress"][
            "validation_v7_present_opaque_bundle_files"
        ]
        == 0
        and iteration531["progress"][
            "validation_v7_required_opaque_bundle_files"
        ]
        == 5
        and iteration531["progress"]["validation_v7_payload_decrypted"]
        is False
        and iteration531["authorization"][
            "required_arms_production_integrated"
        ]
        == 10
        and iteration531["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.31 fail-closed verdict changed",
    )
    require(
        validation_v7_privacy_audit["status"]
        == "VALIDATION_V7_V1_PRIVACY_DEFECT_CONFIRMED_NO_REAL_EXPOSURE"
        and all(validation_v7_privacy_audit["checks"].values())
        and validation_v7_privacy_audit["observed"][
            "raw_source_tree_digest_dictionary_identified"
        ]
        is True
        and validation_v7_privacy_audit["observed"][
            "salted_domain_separated_commitment_matches_raw_dictionary"
        ]
        is False
        and validation_v7_privacy_audit["observed"][
            "real_source_tree_digests_observed"
        ]
        == 0
        and validation_v7_privacy_audit["decision"][
            "validation_v7_identity_intake_v1_allowed_for_real_bundle"
        ]
        is False
        and validation_v7_privacy_audit["decision"][
            "validation_v7_identity_intake_v2_required"
        ]
        is True
        and validation_v7_privacy_audit["decision"]["P6_advanced"] is False,
        "validation-v7 identity privacy audit changed",
    )
    v7_v2_summary = validation_v7_intake_v2["observed"]["summary"]
    require(
        validation_v7_intake_v2["status"]
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING"
        and validation_v7_intake_v2["operationally_valid"] is True
        and all(validation_v7_intake_v2["checks"].values())
        and v7_v2_summary["positive_validators"] == 2
        and v7_v2_summary["hostile_cases"] == 18
        and v7_v2_summary["hostile_rejected_twice"] == 18
        and v7_v2_summary["real_present_required_files"] == 0
        and v7_v2_summary["real_missing_required_files"] == 5
        and validation_v7_intake_v2["observed"]["payload_decrypted"] is False
        and validation_v7_intake_v2["observed"][
            "source_runtime_graph_shape_or_outcome_accessed"
        ]
        is False
        and validation_v7_intake_v2["decision"]["v1_retired"] is True
        and validation_v7_intake_v2["decision"]["P2_advanced"] is False
        and validation_v7_intake_v2["decision"]["P6_advanced"] is False
        and validation_v7_intake_v2["decision"][
            "prospective_trial_authorized"
        ]
        is False,
        "validation-v7 identity-only v2 intake changed",
    )
    require(
        iteration532["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration532["prerequisites"].values()) == 5
        and iteration532["prerequisites"][
            "P6_unchanged_prospective_freeze"
        ]
        is False
        and iteration532["progress"]["P6_complete"] is False
        and iteration532["progress"]["production_integrated_arms"] == 10
        and iteration532["progress"][
            "validation_v7_identity_only_v1_real_bundle_acceptance_forbidden"
        ]
        is True
        and iteration532["progress"][
            "validation_v7_identity_only_v2_protocol_frozen"
        ]
        is True
        and iteration532["progress"][
            "validation_v7_v2_source_tree_commitment_salted_and_domain_separated"
        ]
        is True
        and iteration532["progress"][
            "validation_v7_v2_hostile_cases_rejected_twice"
        ]
        == 18
        and iteration532["progress"][
            "validation_v7_v2_present_opaque_bundle_files"
        ]
        == 0
        and iteration532["progress"]["validation_v7_v2_intake_complete"]
        is False
        and iteration532["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.32 fail-closed verdict changed",
    )
    require(
        validation_v7_provenance_v1_audit["status"]
        == "PROVENANCE_V1_ENFORCEMENT_GAPS_CONFIRMED_NO_EXTERNAL_ARTIFACTS"
        and all(validation_v7_provenance_v1_audit["checks"].values())
        and validation_v7_provenance_v1_audit["observed"][
            "source_choice_root_field_named"
        ]
        is True
        and validation_v7_provenance_v1_audit["observed"][
            "source_choice_root_construction_defined"
        ]
        is False
        and validation_v7_provenance_v1_audit["observed"][
            "candidate_roster_leaf_contract_defined"
        ]
        is False
        and validation_v7_provenance_v1_audit["decision"][
            "provenance_v1_allowed_for_real_attestation"
        ]
        is False
        and validation_v7_provenance_v1_audit["decision"][
            "provenance_v2_required"
        ]
        is True
        and validation_v7_provenance_v1_audit["decision"]["P6_advanced"]
        is False,
        "validation-v7 provenance v1 enforcement audit changed",
    )
    provenance_v2_summary = validation_v7_provenance_v2["observed"]["summary"]
    provenance_v2_positive = validation_v7_provenance_v2["observed"][
        "synthetic_positive"
    ]
    require(
        validation_v7_provenance_v2["status"]
        == "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT"
        and validation_v7_provenance_v2["operationally_valid"] is True
        and all(validation_v7_provenance_v2["checks"].values())
        and provenance_v2_summary["positive_validators"] == 2
        and provenance_v2_summary["hostile_cases"] == 26
        and provenance_v2_summary["hostile_rejected_twice"] == 26
        and provenance_v2_summary["real_trust_root_present"] is False
        and provenance_v2_summary["real_bundle_files_present"] == 0
        and provenance_v2_summary["real_provenance_files_present"] == 0
        and provenance_v2_positive["signatures_verified"] == 4
        and provenance_v2_positive["roster_nonmembership_checks"] == 2
        and provenance_v2_positive["source_count"] == 4
        and provenance_v2_positive[
            "social_independence_cryptographically_proved"
        ]
        is False
        and validation_v7_provenance_v2["decision"][
            "accountable_provenance_v2_mechanism_conformant"
        ]
        is True
        and validation_v7_provenance_v2["decision"][
            "real_accountable_provenance_attested"
        ]
        is False
        and validation_v7_provenance_v2["decision"]["P2_advanced"] is False
        and validation_v7_provenance_v2["decision"]["P6_advanced"] is False
        and validation_v7_provenance_v2["decision"][
            "prospective_trial_authorized"
        ]
        is False,
        "validation-v7 accountable provenance v2 result changed",
    )
    require(
        iteration533["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration533["prerequisites"].values()) == 5
        and iteration533["prerequisites"][
            "P6_unchanged_prospective_freeze"
        ]
        is False
        and iteration533["progress"]["P6_complete"] is False
        and iteration533["progress"]["production_integrated_arms"] == 10
        and iteration533["progress"][
            "validation_v7_provenance_v1_real_attestation_forbidden"
        ]
        is True
        and iteration533["progress"][
            "validation_v7_accountable_provenance_v2_protocol_frozen"
        ]
        is True
        and iteration533["progress"][
            "validation_v7_accountable_provenance_v2_hostile_rejected_twice"
        ]
        == 26
        and iteration533["progress"][
            "validation_v7_real_sponsor_trust_root_present"
        ]
        is False
        and iteration533["progress"][
            "validation_v7_real_provenance_files_present"
        ]
        == 0
        and iteration533["progress"][
            "validation_v7_real_accountable_provenance_attested"
        ]
        is False
        and iteration533["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.33 fail-closed verdict changed",
    )
    local_grammar_summary = local_grammar["observed"]["summary"]
    require(
        local_grammar["status"] == "LOCAL_GRAMMAR_EMERGENCE_VALID_NEGATIVE"
        and local_grammar["operationally_valid"] is True
        and all(local_grammar["checks"].values())
        and local_grammar_summary["training_connected_subsets"] == 375
        and local_grammar_summary["heldout_connected_subsets"] == 1539
        and local_grammar_summary["selected_productions"] == 27
        and local_grammar_summary["selected_non_chain_productions"] == 3
        and local_grammar_summary["selected_tools"] == 9
        and local_grammar_summary["candidate_only_heldout_nodes"] == 0
        and local_grammar["decision"]["P6_advanced"] is False,
        "local connected-DAG grammar result changed",
    )
    local_template_summary = local_template["observed"]["summary"]
    require(
        local_template["status"] == "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
        and local_template["operationally_valid"] is True
        and all(local_template["checks"].values())
        and local_template_summary["selected_templates"] == 1
        and local_template_summary["operator_holes"] == 2
        and local_template_summary["recipe_holes"] == 2
        and local_template_summary["candidate_only_template_matches"] == 2
        and local_template_summary["candidate_only_template_nodes"] == 3
        and local_template["decision"]["concrete_exact_tool_reuse_demonstrated"]
        is False
        and local_template["decision"]["runtime_primitive_invented"] is False
        and local_template["decision"]["P6_advanced"] is False,
        "local typed-template transfer result changed",
    )
    local_information_summary = local_informativeness["observed"]["summary"]
    require(
        local_informativeness["status"]
        == "LOCAL_TYPED_TEMPLATE_STRUCTURAL_ONLY_VALID_NEGATIVE"
        and local_informativeness["operationally_valid"] is True
        and all(local_informativeness["checks"].values())
        and local_information_summary["candidate_heldout_matches"] == 2
        and local_information_summary["topology_only_heldout_matches"] == 2
        and local_information_summary["typed_rejections"] == 0
        and local_information_summary["candidate_information_bits"] == 0.0
        and local_information_summary["boundary_only_heldout_matches"] == 17
        and local_information_summary["frequency_baseline_heldout_matches"] == 19
        and local_information_summary["unseen_operator_pairs"] == 2
        and local_informativeness["decision"][
            "typed_constraint_added_heldout_information"
        ]
        is False
        and local_informativeness["decision"]["P6_advanced"] is False,
        "local template-informativeness result changed",
    )
    require(
        iteration534["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration534["prerequisites"].values()) == 5
        and iteration534["progress"]["production_integrated_arms"] == 10
        and iteration534["progress"][
            "local_connected_dag_grammar_executed"
        ]
        is True
        and iteration534["progress"][
            "local_typed_template_transfer_executed"
        ]
        is True
        and iteration534["progress"][
            "local_template_informativeness_ablation_executed"
        ]
        is True
        and iteration534["progress"]["local_template_typed_rejections"] == 0
        and iteration534["progress"]["local_template_information_bits"] == 0.0
        and iteration534["progress"]["local_template_structural_only"] is True
        and iteration534["authorization"]["prospective_trial_authorized"]
        is False,
        "iteration 5.34 fail-closed verdict changed",
    )
    operator_summary = local_operator_prediction["observed"]["summary"]
    require(
        local_operator_prediction["status"] == "LOCAL_OPERATOR_PREDICTION_POSITIVE"
        and local_operator_prediction["operationally_valid"] is True
        and all(local_operator_prediction["checks"].values())
        and operator_summary["eligible_heldout_motifs"] == 279
        and operator_summary["candidate_exact_sequences"] == 18
        and operator_summary["boundary_exact_sequences"] == 0
        and operator_summary["global_exact_sequences"] == 0
        and operator_summary["candidate_exact_families"] == 11
        and operator_summary["candidate_exact_folds"] == 5
        and local_operator_prediction["decision"]["P6_advanced"] is False,
        "local operator-prediction result changed",
    )
    body_summary = local_exact_body_prediction["observed"]["summary"]
    require(
        local_exact_body_prediction["status"]
        == "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
        and local_exact_body_prediction["operationally_valid"] is True
        and all(local_exact_body_prediction["checks"].values())
        and body_summary["candidate_exact_bodies"] == 17
        and body_summary["boundary_exact_bodies"] == 4
        and body_summary["global_exact_bodies"] == 4
        and body_summary["candidate_exact_families"] == 10
        and body_summary["candidate_exact_folds"] == 4
        and local_exact_body_prediction["decision"][
            "tool_execution_demonstrated"
        ]
        is False,
        "local exact-body prediction result changed",
    )
    execution_summary = local_exact_tool_execution["observed"]["summary"]
    require(
        local_exact_tool_execution["status"]
        == "LOCAL_EXACT_TOOL_EXECUTION_VALID_STOCK_DUPLICATE"
        and local_exact_tool_execution["operationally_valid"] is True
        and all(local_exact_tool_execution["checks"].values())
        and execution_summary["candidate_exact_rows"] == 17
        and execution_summary["stock_exact_rows"] == 17
        and execution_summary["declared_outputs_checked"] == 17
        and execution_summary["causal_matches_after_remove_all"] == 0
        and execution_summary["native_compile_rows"] == 3
        and execution_summary["normalized_inductor_duplicates"] == 3
        and execution_summary["runtime_inventions_admitted"] == 0
        and local_exact_tool_execution["decision"][
            "concrete_exact_tool_reuse_executed"
        ]
        is True
        and local_exact_tool_execution["decision"]["lower_total_cost_demonstrated"]
        is False
        and local_exact_tool_execution["decision"]["P6_advanced"] is False,
        "local exact-tool execution result changed",
    )
    require(
        iteration535["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration535["prerequisites"].values()) == 5
        and iteration535["progress"]["local_operator_exact_sequences"] == 18
        and iteration535["progress"]["local_exact_body_predictions"] == 17
        and iteration535["progress"]["local_exact_tool_real_value_replays"] == 17
        and iteration535["progress"]["local_exact_tool_native_duplicates"] == 3
        and iteration535["progress"]["local_exact_tool_runtime_inventions"] == 0
        and iteration535["authorization"]["prospective_trial_authorized"] is False,
        "iteration 5.35 fail-closed verdict changed",
    )
    utility_summary = local_exact_tool_utility["observed"]["summary"]
    require(
        local_exact_tool_utility["status"] == "LOCAL_EXACT_TOOL_UTILITY_POSITIVE"
        and local_exact_tool_utility["operationally_valid"] is True
        and all(local_exact_tool_utility["checks"].values())
        and utility_summary["candidate_total_cost"] == 12465
        and utility_summary["fixed_total_cost"] == 2072
        and utility_summary["candidate_unique_nodes"] == 31
        and utility_summary["fixed_unique_nodes"] == 51
        and utility_summary["candidate_only_nodes"] == 9
        and utility_summary["candidate_only_families"] == 8
        and utility_summary["candidate_cheaper"] is False
        and utility_summary["candidate_more_efficient"] is False
        and local_exact_tool_utility["decision"][
            "locally_newly_reachable_nodes_demonstrated"
        ]
        is True
        and local_exact_tool_utility["decision"][
            "prospective_real_world_discovery_demonstrated"
        ]
        is False
        and local_exact_tool_utility["decision"]["P6_advanced"] is False,
        "local exact-tool utility result changed",
    )
    require(
        iteration536["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(iteration536["prerequisites"].values()) == 5
        and iteration536["progress"]["local_exact_tool_candidate_total_cost"] == 12465
        and iteration536["progress"]["local_exact_tool_fixed_total_cost"] == 2072
        and iteration536["progress"]["local_exact_tool_candidate_only_nodes"] == 9
        and iteration536["progress"]["local_exact_tool_candidate_only_families"] == 8
        and iteration536["progress"]["local_exact_tool_candidate_cheaper"] is False
        and iteration536["progress"]["local_exact_tool_bounded_new_reach"] is True
        and iteration536["progress"]["local_exact_tool_prospective_discovery"] is False
        and iteration536["authorization"]["prospective_trial_authorized"] is False,
        "iteration 5.36 fail-closed verdict changed",
    )
    require(
        goal_continuation536["status"]
        == "LOCAL_REMEDIATION_COMPLETE_WAITING_EXTERNAL_PREDECESSORS"
        and goal_continuation536["local_work_remaining_before_external_intake"] == []
        and goal_continuation536["external_predecessors"][
            "out_of_band_verified_sponsor_fingerprint"
        ]
        is False
        and goal_continuation536["external_predecessors"][
            "validation_v7_v2_bundle_present"
        ]
        == 0
        and goal_continuation536["external_predecessors"][
            "accountable_provenance_v2_present"
        ]
        == 0
        and goal_continuation536["authorization"]["P6_advanced"] is False
        and goal_continuation536["authorization"]["V08_measurement_passed"] is False
        and goal_continuation536["authorization"]["prospective_trial_authorized"]
        is False,
        "goal continuation audit 5.36 changed",
    )

    print(
        "FOUNDRY_1_VERIFY_PASS"
        " tools=4 phase1=4/4 phase2=4/4 fixed=4/4"
        f" gates={readiness['gates_passed']}/{readiness['gates_total']}"
        f" dedup={ds['plans']}_plans/{ds['representative_signatures']}_signatures"
        f" external_graphs={cs['exported']}"
        f" historical_intake_controls_reproduced={intake['conformance_executed']}/4"
        " local_meter=PASS"
        f" seed_tools_admitted={admission_summary['ADMIT']}"
        f" tensor_tools={tensor_forge['tools_forged']}"
        f" tensor_transfers={tensor_eval['successful_transfers']}"
        f" tensor_tools_admitted={tensor_native['P5']['admitted']}"
        " tensor_component_freeze=PASS"
        f" external_apps={external_trace['summary']['families']}"
        f" external_invocations={external_trace['summary']['total_invocations']}"
        f" production_trace_rows={external_invocation_trace['trace']['rows']}"
        f" production_trace_models={external_invocation_trace['trace']['models']}"
        f" N_star={external_invocation_trace['N_star_external_reference']}"
        " trace_replay=12/12"
        " local_trace_blobs=3/3"
        " offline_trace_parsers=2/2"
        " horizon_coordinates=4x3"
        " P2_complete=true"
        " arm_contract=PASS"
        " arm_contract_hostile=9/9"
        " bounded_A3_A9=PASS"
        " bounded_A3_A9_ops=3"
        " calibration_operator_surface=41"
        " runtime_route=FRAMEWORK_MOUNT"
        " framework_mount_graphs=23"
        " framework_mount_ops=41"
        " framework_mount_executions=69/69"
        " framework_mount_error=0"
        " shared_contract_pairs=46/46"
        " shared_resource_receipts=1+1"
        " shared_batch_hostile=9/9"
        " A1_runtime_ops=22"
        " A1_direct_targets=9/41"
        " A1_direct_calls=143/337"
        " A1_direct_graphs=4/23"
        " A1_constructor_patterns=0"
        " A1_direct_adapter=REJECTED"
        " A1_adapted_fold_sites=3"
        " A1_runtime_executions=69"
        " A1_fold_checks=9"
        " A1_contract_pairs=23/23"
        " A1_absolute_phase=FAILED"
        " A1_unseen_numeric=48/48"
        " integrated_arms=8/10"
        " A4_tools=3/3"
        " A4_replays=29"
        " A4_graph_executions=69"
        " A4_error=0"
        " A4_contract_pairs=23/23"
        " A4_shared_receipts=1"
        " A4_hostile=11/11"
        " external_tool_reachability=0/16"
        f" aten_tools={aten_forge['tools_forged']}"
        f" aten_macro_replays={aten_eval['successful_macro_replays']}"
        f" aten_tools_admitted={aten_audit['summary']['admitted']}"
        f" prospective_supported={prospective_v22['supported_families']}/4"
        f" prospective_candidate_matches={prospective_v22['ledgers']['candidate']['matches']}"
        f" prospective_fixed_matches={prospective_v22['ledgers']['fixed']['matches']}"
        " prospective_resource=PASS"
        f" semantic_tools={semantic_forge['tools_forged']}"
        " semantic_supplied_forms=0"
        f" semantic_transfers={semantic_eval['successful_replays']}"
        f" semantic_fixed_matches={semantic_eval['fixed']['matches']}"
        f" semantic_tools_admitted={semantic_native['summary']['admitted']}"
        f" polymorphic_tools={polymorphic_forge['tools']}"
        f" polymorphic_transfers={polymorphic_eval['successful_replays']}"
        f" polymorphic_families={polymorphic_eval['matched_families']}/"
        f"{polymorphic_eval['families']}"
        f" polymorphic_fixed_matches={polymorphic_eval['fixed']['matches']}"
        f" polymorphic_native_duplicates="
        f"{polymorphic_native['summary']['normalized_inductor_duplicates']}"
        f" polymorphic_tools_admitted={polymorphic_native['summary']['admitted']}"
        f" stitch_control={stitch_control['status']}"
        f" current_source_control_arms_metered="
        f"{enumo_source_resource['P3']['metered_source_control_arms']}/4"
        f" current_controls_reproduced="
        f"{enumo_source_resource['P1']['source_faithful_controls_reproduced']}/"
        f"{enumo_source_resource['P1']['controls_required']}"
        " stitch_source_control=PASS"
        " stitch_metamorphic=PASS"
        " enumo_source=18/18"
        " enumo_historical_deps=10/21"
        " enumo_source_control=PASS"
        " enumo_official_boolean=43/43"
        " enumo_metamorphic_exact_set=FAIL"
        " enumo_rules=60_to_67"
        " enumo_bounded_power=67/67,60/60"
        " control_four_route=ISAMORE"
        " control_four_executable=false"
        " isamore_registry_deps=14/30"
        " isamore_gitlinks=4/4"
        " isamore_source_records=29/29"
        " isamore_published_workload=PASS"
        " isamore_metadata=PASS"
        " isamore_colored_bridge=OFFICIAL_TAG"
        " isamore_crossbeam_bridge=MIXED_AUTHENTICATED"
        " isamore_csv_tag_bridge=27/27"
        " isamore_env_logger_roots=3/3"
        " isamore_env_logger_tag_records=37/37"
        " isamore_graphviz_family=5/5"
        " isamore_graphviz_source_records=16/16"
        " isamore_indicatif_family=4/4"
        " isamore_indicatif_source_records=35/35"
        " isamore_build_stop=kiddo"
        " isamore_csv_closure=7/11"
        " isamore_env_logger_closure=14/31"
        " isamore_graphviz_closure=57/77"
        " isamore_indicatif_closure=18/31"
        " isamore_kiddo_closure=34/56"
        " isamore_kiddo_root_acquisition=AVAILABLE_CHANNELS_NO_SOURCE"
        " isamore_kiddo_partial_family=4/8"
        " isamore_kiddo_partial_source_records=20/20"
        " isamore_divrem_source_compile=PASS"
        " isamore_remaining_math_sources=0/3"
        " isamore_divergent_mirror_substituted=false"
        " isamore_coin_cbc_bindings=2/2"
        " isamore_coin_cbc_source_records=7/7"
        " isamore_coin_cbc_rust_compile=PASS"
        " isamore_native_cbc=false"
        " isamore_pinned_nightly=false"
        " isamore_coin_cbc_solver_executed=false"
        " isamore_native_cbc_candidate=2.10.11"
        " isamore_native_cbc_downloaded=false"
        " isamore_native_cbc_installed=false"
        " isamore_exact_archive_transport=0/4"
        " isamore_substitute_source_accepted=false"
        " isamore_control_executed=false"
        " isamore_reduced_route=REJECTED"
        " diversity_calibration_graphs=19/20"
        " diversity_patterns=149"
        " diversity_novel_sequences=6"
        " diversity_repository_novel=1"
        " diversity_v5_graphs=4/4"
        " diversity_v5_tools=2/3"
        " diversity_v5_families=3/4"
        " diversity_v5_benefit=11/13"
        " diversity_v5_cost=294/244"
        " diversity_v5_candidate_only_families=0"
        " diversity_v5_result=VALID_NEGATIVE"
        " diversity_native_admitted=0"
        " diversity_failure_coverage_deficit=2"
        " diversity_equal_cohort_break_even=2"
        " pareto_calibration_graphs=23"
        " pareto_paths=581"
        " pareto_tools=4"
        " pareto_calibration_benefit=53/51"
        " pareto_calibration_cost=2234/2616"
        " pareto_native_admitted=0"
        " pareto_authorization=DENIED"
        " pareto_prerequisites=5/6"
        " pareto_integrated_arms=6/10"
        " A1_opaque_reference_fallback=REJECTED"
        " enumo_tensor_feasibility=PASS"
        " enumo_tensor_rules=18"
        " enumo_tensor_independent_lanes=1176"
        " enumo_tensor_heldout=3339"
        " enumo_tensor_learned_wins=0"
        " enumo_tensor_fixed_wins=736"
        " enumo_tensor_A7_integrated=false"
        " autonomous_typed_grammar=ALREADY_ESTABLISHED"
        " V08_search_receipt_fields=22"
        " V08_hostile_ledgers=15/15"
        " V08_measurement=PENDING"
        " native_dedup_terminal_stop=false"
        " pending_trial_validity_measurements=1"
        " P3_complete=true"
        " unsupported_contract_pairs=92/92"
        " pareto_historical_active_stops=1"
        " validation_v6_source_runtime_graph_access=false"
        " eggmind_official_repositories=0"
        " eggmind_adapted_boundary=PASS"
        " eggmind_A8_full=false"
        " eggmind_specified_missing=10/16"
        " isamore_ingress_locked=310"
        " isamore_ingress_hostile=11/11"
        " isamore_ingress_exact=0"
        " sympy_cse_official=61/61"
        " sympy_cse_numeric=30/30"
        " sympy_cse_hostile=10/10"
        " source_controls=4/4"
        " foundry0_prerequisites=6/6"
        " A7_real_graph_calls=53"
        " A7_real_graph_matches=282"
        " A7_raw_selected=24"
        " A7_unique_transformations=12"
        " A7_whole_graph_executions=69"
        " A7_rewrite_checks=36"
        " A7_contract_pairs=23/23"
        " A7_batch_hostile=22/22"
        " A7_strict_reductions=0"
        " A7_current_integrated=true"
        " current_integrated_arms=10/10"
        " A6_reachability=337x56616"
        " A6_selected_sites=12"
        " A6_tool_calls=36"
        " A6_fixed_duplicate=true"
        " A8_strategies=40320"
        " A8_applications=22_to_20"
        " A8_tool_calls=60"
        " validation_v6_chronology=INVALIDATED"
        " validation_v6_executed=false"
        " validation_v7_intake=WAITING"
        " validation_v7_files=0/5"
        " validation_v7_hostile=16/16"
        " validation_v7_decrypted=false"
        " validation_v7_v1=RETIRED_PRIVACY_DEFECT"
        " validation_v7_v2=WAITING"
        " validation_v7_v2_files=0/5"
        " validation_v7_v2_hostile=18/18"
        " validation_v7_provenance_v1=RETIRED_UNENFORCEABLE"
        " validation_v7_provenance_v2=CONFORMANT"
        " validation_v7_provenance_hostile=26/26"
        " validation_v7_real_trust=false"
        " validation_v7_real_provenance=0/13"
        " current_prerequisites=5/6"
        " local_connected_dag_productions=27"
        " local_non_chain_productions=3"
        " local_exact_candidate_only_nodes=0"
        " local_template_matches=2"
        " local_template_candidate_only_nodes=3"
        " local_template_typed_rejections=0"
        " local_template_information_bits=0"
        " local_template_result=STRUCTURAL_ONLY"
        " local_operator_exact=18"
        " local_exact_bodies=17"
        " local_exact_replays=17/17"
        " local_exact_native_duplicates=3"
        " local_exact_runtime_inventions=0"
        " local_utility_cost=12465/2072"
        " local_utility_nodes=31/51"
        " local_utility_candidate_only=9"
        " local_utility_families=8"
        " local_utility_prospective=false"
        " A1_connected_subgraphs=7093"
        " A1_semantic_candidates=6"
        " A1_candidate_families=2"
        " A1_pattern_first_lowering=JUSTIFIED"
        " A1_reachability_stage_constructor_executed=false"
        " A1_current_constructor_executed=true"
        " A1_initial_dense_false_positives=3"
        " A1_direction_rejected_dense=3"
        " A1_corrected_candidates=3"
        " A1_corrected_family=fold_conv_batch_norm"
        " A3_A9_search=969/969"
        " A3_A9_coverage=126/226"
        " A3_A9_prospective=false"
        " control_two_route=babble_popl23"
        " babble_source_control=PASS"
        " babble_readme_cost_exact=false"
        " babble_metamorphic=PASS"
        " control_two_executed=true"
        " verdict=FOUNDRY_V6_NOT_READY"
    )


if __name__ == "__main__":
    main()
