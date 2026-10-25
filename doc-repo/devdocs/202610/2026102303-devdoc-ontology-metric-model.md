---
Date: 2026/10/23
Contributors: ChatGPT, Chen Ding
---

# 1. Overview
This document outlines a Metric Kind Taxonomy that classifies metrics extracted from standards, technical specifications, test reports, regulations, and scientific documents.

# 2. Ontology
Metrics can be classified as test_setting, test_condition, product_specification, 
metrological_characteristic, dimension, data_format, performance, resolution, pressure, 
permitted_error, etc. Some of them are metric roles:
- `test_settings`
- `product_specification`
- `metrological_characteristics`

Some describe what is being measured or specified:
- `pressure`
- `dimension`
- `resolution`
- `permitted_error`

These are different classification dimensions. Mixing them into one hierarchy will produce overlapping categories and make automated classification difficult.

A comprehensive taxonomy is organized into three dimensions:

1. Metric Role — Why is the quantity specified?
2. Metric Kind — What property or characteristic does the quantity represent?
3. Metric Value Type — How is the quantity represented?

There is no universally exhaustive list of metric kinds across all scientific and engineering domains. 
This document proposes a broad, extensible taxonomy intended for practical knowledge extraction.
The figure below shows its high-level structure.

![Metric Ontology](../../../Images/image_2026102401.png)

Metric ontology follows the following principles.

**1. Distinguish a quantity from its measurement characteristics**

`pressure` is a quantity kind; `pressure_accuracy` is a metrological characteristic of a measurement of pressure. This avoids creating separate top-level classes for every combination.

**2. Distinguish a metric definition from a metric assertion**

The metric `operating_temperature` may be defined once, but hundreds of standards may assert different operating temperature limits. Those assertions should retain their source, subject, conditions, and applicability.

**3. Support multiple roles**

A value of 5 MPa may simultaneously be a `product_specification`, `operating_limit`, 
and `safety_limit`. These roles should not necessarily be mutually exclusive.

**4. Distinguish kind from statistical transformation**

`mean_pressure`, `maximum_pressure`, and `p95_pressure` are all about pressure, with different aggregation functions. Model the aggregation separately when possible.

**5. Extensibility**

Use `metric_kind` as a hierarchical, extensible ontology, while treating `metric_role`, 
`value_type`, and `metric_domain` as separate classification dimensions.

**6. Use established vocabularies**

Align the physical quantity kinds with established vocabularies such as QUDT and the 
IEC/ISO International Vocabulary of Metrology (VIM). QUDT is particularly useful for 
quantity kinds and units, while VIM provides precise definitions for concepts such 
as measurement uncertainty, repeatability, and maximum permissible measurement error.

This gives the ontology that is both broad enough for general standards and precise 
enough for metrology, engineering, software, and regulatory compliance.

# 3. Metric Role Taxonomy

This dimension describes the function of a metric within a document.

| Category           | Metric kinds                                                                                                                                      | Examples                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Specification      | `product_specification`, `component_specification`, `material_specification`, `system_specification`, `interface_specification`                   | Rated voltage, device dimensions |
| Test configuration | `test_setting`, `test_condition`, `test_parameter`, `test_duration`, `test_environment`, `test_load`, `test_frequency`, `test_sample_size`        | Test temperature 23 °C           |
| Metrology          | `metrological_characteristic`, `measurement_range`, `measurement_uncertainty`, `measurement_accuracy`, `calibration_parameter`, `reference_value` | Measurement uncertainty ±0.2 °C  |
| Performance        | `performance_requirement`, `performance_indicator`, `performance_limit`, `performance_target`, `performance_result`, `performance_benchmark`      | Throughput 500 requests/s        |
| Quality            | `quality_characteristic`, `quality_indicator`, `quality_limit`, `acceptance_criterion`, `defect_rate`, `conformance_level`                        | Defect rate below 0.1%           |
| Safety             | `safety_limit`, `exposure_limit`, `hazard_threshold`, `protection_threshold`, `safety_margin`, `emergency_threshold`                              | Maximum exposure 85 dB           |
| Environmental      | `environmental_condition`, `environmental_limit`, `operating_environment`, `storage_condition`, `transport_condition`                             | Storage humidity below 60% RH    |
| Operating          | `operating_parameter`, `operating_limit`, `operating_range`, `operating_setpoint`, `control_parameter`, `process_parameter`                       | Operating pressure 2 MPa         |
| Manufacturing      | `manufacturing_parameter`, `process_setting`, `process_tolerance`, `production_capacity`, `material_consumption`, `yield_target`                  | Welding temperature 250 °C       |
| Reliability        | `reliability_characteristic`, `failure_rate`, `service_life`, `durability_requirement`, `maintenance_interval`, `availability_target`             | MTBF 50,000 hours                |
| Compliance         | `regulatory_limit`, `mandatory_requirement`, `recommended_value`, `compliance_threshold`, `certification_criterion`                               | Emissions below 50 mg/m³         |
| Data/interface     | `data_format`, `data_resolution`, `data_precision`, `sampling_rate`, `data_capacity`, `communication_rate`                                        | Sampling rate 100 Hz             |
| Monitoring         | `monitoring_parameter`, `alarm_threshold`, `warning_threshold`, `trigger_condition`, `reporting_interval`, `monitoring_frequency`                 | Alarm above 8 °C                 |
| Statistical        | `statistical_indicator`, `statistical_estimate`, `confidence_interval`, `percentile`, `distribution_parameter`, `sample_statistic`                | P95 latency 200 ms               |
| Resource           | `resource_consumption`, `resource_capacity`, `energy_consumption`, `material_usage`, `resource_efficiency`                                        | Energy consumption 5 kWh         |
| Economic           | `cost_metric`, `price_metric`, `economic_efficiency`, `return_metric`, `lifecycle_cost`                                                           | Cost per unit $25                |
| Observed result    | `measured_value`, `observed_value`, `calculated_value`, `estimated_value`, `predicted_value`, `simulation_result`                                 | Measured pressure 1.98 MPa       |

The last row describes a metric's evidential status or provenance rather than its intended function. In a stricter ontology, I would model it as a separate dimension.

# 4. Metric Kind Taxonomy

This is the main taxonomy for identifying what a metric measures or describes.

Each category can be expanded into more specialized metric kinds.

### 4.1 Physical and mechanical quantities

| Category              | Metric kinds                                                                                                                                                                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Geometry              | `dimension`, `length`, `width`, `height`, `depth`, `thickness`, `diameter`, `radius`, `distance`, `perimeter`, `area`, `volume`, `angle`, `curvature`, `flatness`, `roundness`, `straightness`, `surface_roughness` |
| Mass                  | `mass`, `weight`, `density`, `mass_flow_rate`, `mass_fraction`, `mass_concentration`, `mass_per_unit_area`                                                                                                          |
| Motion                | `position`, `displacement`, `velocity`, `speed`, `acceleration`, `angular_velocity`, `angular_acceleration`, `rotational_speed`, `vibration`, `oscillation`                                                         |
| Force                 | `force`, `load`, `torque`, `moment`, `thrust`, `tension`, `compression`, `shear_force`, `friction_force`                                                                                                            |
| Pressure              | `pressure`, `absolute_pressure`, `gauge_pressure`, `differential_pressure`, `vacuum_pressure`, `pressure_drop`, `pressure_gradient`                                                                                 |
| Mechanical properties | `stress`, `strain`, `elastic_modulus`, `yield_strength`, `tensile_strength`, `compressive_strength`, `shear_strength`, `hardness`, `toughness`, `ductility`, `fatigue_strength`, `creep_rate`                       |
| Flow                  | `flow_rate`, `volumetric_flow_rate`, `flow_velocity`, `flow_resistance`, `viscosity`, `permeability`, `turbulence`, `reynolds_number`                                                                               |

## 4.2 Thermal and thermodynamic quantities

| Category       | Metric kinds                                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Temperature    | `temperature`, `temperature_difference`, `temperature_range`, `temperature_gradient`, `temperature_stability`, `temperature_uniformity`                        |
| Heat           | `heat`, `heat_flux`, `heat_capacity`, `specific_heat_capacity`, `thermal_conductivity`, `thermal_resistance`, `thermal_expansion`, `heat_transfer_coefficient` |
| Thermodynamics | `entropy`, `enthalpy`, `internal_energy`, `gibbs_free_energy`, `thermal_efficiency`, `coefficient_of_performance`                                              |
| Phase change   | `melting_point`, `boiling_point`, `freezing_point`, `flash_point`, `latent_heat`, `vapor_pressure`                                                             |

## 4.3 Electrical, magnetic, and electromagnetic quantities

| Category              | Metric kinds                                                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Electrical            | `voltage`, `current`, `resistance`, `conductance`, `impedance`, `capacitance`, `inductance`, `electric_charge`, `electric_field_strength`  |
| Power                 | `power`, `active_power`, `reactive_power`, `apparent_power`, `power_factor`, `energy`, `energy_efficiency`                                 |
| Frequency and signals | `frequency`, `period`, `phase`, `phase_shift`, `amplitude`, `signal_strength`, `signal_to_noise_ratio`, `harmonic_distortion`, `bandwidth` |
| Magnetic              | `magnetic_flux`, `magnetic_flux_density`, `magnetic_field_strength`, `magnetic_permeability`, `magnetization`                              |
| Electromagnetic       | `electromagnetic_field_strength`, `radiated_power`, `emission_level`, `electromagnetic_interference`, `shielding_effectiveness`            |

## 4.4 Optical, acoustic, and radiation quantities

| Category  | Metric kinds                                                                                                                                         |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Optical   | `wavelength`, `luminous_flux`, `luminous_intensity`, `illuminance`, `luminance`, `reflectance`, `transmittance`, `refractive_index`, `optical_power` |
| Imaging   | `image_resolution`, `spatial_resolution`, `pixel_density`, `contrast_ratio`, `dynamic_range`, `frame_rate`, `field_of_view`                          |
| Acoustic  | `sound_pressure_level`, `sound_power_level`, `noise_level`, `acoustic_frequency`, `acoustic_impedance`, `reverberation_time`                         |
| Radiation | `radiation_dose`, `absorbed_dose`, `equivalent_dose`, `effective_dose`, `dose_rate`, `radioactivity`, `particle_flux`, `radiation_intensity`         |

## 4.5 Chemical, biological, and environmental quantities

| Category                  | Metric kinds                                                                                                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chemical composition      | `concentration`, `molar_concentration`, `mass_concentration`, `mole_fraction`, `purity`, `impurity_level`, `composition_ratio`                                                  |
| Chemical properties       | `ph`, `acidity`, `alkalinity`, `conductivity`, `solubility`, `reactivity`, `oxidation_reduction_potential`, `reaction_rate`                                                     |
| Biological                | `cell_count`, `microbial_count`, `viability`, `biological_activity`, `enzyme_activity`, `growth_rate`, `inhibition_rate`                                                        |
| Environmental             | `humidity`, `relative_humidity`, `air_quality_index`, `particulate_concentration`, `pollutant_concentration`, `emission_rate`, `water_quality`, `turbidity`, `dissolved_oxygen` |
| Medical and physiological | `heart_rate`, `blood_pressure`, `respiratory_rate`, `oxygen_saturation`, `body_temperature`, `blood_glucose`, `drug_concentration`, `clearance_rate`                            |

## 4.6 Time, frequency, and temporal quantities

| Category  | Metric kinds                                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Time      | `time`, `duration`, `elapsed_time`, `delay`, `latency`, `response_time`, `reaction_time`, `recovery_time`, `startup_time`      |
| Frequency | `frequency`, `event_frequency`, `sampling_frequency`, `measurement_frequency`, `inspection_frequency`, `maintenance_frequency` |
| Timing    | `time_interval`, `time_resolution`, `timing_accuracy`, `clock_drift`, `jitter`, `synchronization_error`, `timeout`             |
| Lifecycle | `service_life`, `shelf_life`, `retention_period`, `warranty_period`, `replacement_interval`, `degradation_rate`                |

## 4.7 Metrological characteristics

These are particularly important for extracting metrics from measurement standards.

| Category           | Metric kinds                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accuracy and error | `accuracy`, `measurement_error`, `absolute_error`, `relative_error`, `permitted_error`, `maximum_permissible_error`, `systematic_error`, `random_error`, `bias`, `offset_error` |
| Precision          | `precision`, `repeatability`, `reproducibility`, `intermediate_precision`, `standard_deviation`, `coefficient_of_variation`                                                     |
| Resolution         | `resolution`, `display_resolution`, `measurement_resolution`, `spatial_resolution`, `temporal_resolution`, `quantization_step`                                                  |
| Sensitivity        | `sensitivity`, `detection_limit`, `limit_of_quantification`, `response_threshold`, `sensitivity_coefficient`                                                                    |
| Range              | `measurement_range`, `indication_range`, `operating_range`, `dynamic_range`, `lower_limit`, `upper_limit`, `span`                                                               |
| Stability          | `stability`, `drift`, `zero_drift`, `span_drift`, `long_term_stability`, `short_term_stability`                                                                                 |
| Linearity          | `linearity`, `nonlinearity`, `linearity_error`, `hysteresis`, `dead_band`, `dead_zone`                                                                                          |
| Uncertainty        | `measurement_uncertainty`, `standard_uncertainty`, `combined_standard_uncertainty`, `expanded_uncertainty`, `coverage_factor`                                                   |
| Calibration        | `calibration_factor`, `calibration_offset`, `correction_factor`, `reference_value`, `traceability_parameter`                                                                    |
| Dynamic response   | `response_time`, `rise_time`, `fall_time`, `settling_time`, `time_constant`, `overshoot`                                                                                        |

## 4.8 Performance and reliability characteristics

| Category       | Metric kinds                                                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Performance    | `throughput`, `latency`, `response_time`, `processing_speed`, `capacity`, `utilization`, `efficiency`, `productivity`                                         |
| Reliability    | `failure_rate`, `failure_probability`, `mean_time_between_failures`, `mean_time_to_failure`, `mean_time_to_repair`, `availability`, `reliability_probability` |
| Durability     | `service_life`, `cycle_life`, `fatigue_life`, `wear_rate`, `degradation_rate`, `aging_rate`, `corrosion_rate`                                                 |
| Capacity       | `storage_capacity`, `load_capacity`, `processing_capacity`, `maximum_capacity`, `rated_capacity`, `buffer_capacity`                                           |
| Resource usage | `memory_usage`, `cpu_utilization`, `disk_usage`, `network_utilization`, `power_consumption`, `energy_consumption`                                             |
| Quality        | `defect_rate`, `error_rate`, `rejection_rate`, `yield`, `conformance_rate`, `success_rate`, `pass_rate`                                                       |

## 4.9 Information, computing, and communication characteristics

| Category            | Metric kinds                                                                                                           |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Data representation | `data_format`, `data_type`, `bit_depth`, `word_length`, `numeric_precision`, `encoding`, `character_set`               |
| Data size           | `data_size`, `file_size`, `record_size`, `packet_size`, `message_size`, `storage_capacity`                             |
| Data rates          | `bit_rate`, `data_rate`, `transfer_rate`, `sampling_rate`, `update_rate`, `refresh_rate`                               |
| Network             | `bandwidth`, `network_latency`, `packet_loss_rate`, `jitter`, `round_trip_time`, `connection_count`                    |
| Computing           | `execution_time`, `processing_time`, `instruction_rate`, `operations_per_second`, `memory_bandwidth`, `cache_hit_rate` |
| Information quality | `data_completeness`, `data_accuracy`, `data_consistency`, `data_freshness`, `error_rate`                               |
| Security            | `key_length`, `entropy`, `authentication_failure_rate`, `vulnerability_count`, `detection_rate`                        |

Some items here, such as `data_format`, `encoding`, and `data_type`, are categorical properties rather than quantitative metrics. They are useful to extract, but should be explicitly distinguished from quantities.

## 4.10 Statistical and mathematical characteristics

| Category         | Metric kinds                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Central tendency | `mean`, `median`, `mode`, `geometric_mean`, `weighted_mean`                                       |
| Dispersion       | `variance`, `standard_deviation`, `range`, `interquartile_range`, `coefficient_of_variation`      |
| Distribution     | `percentile`, `quantile`, `skewness`, `kurtosis`, `distribution_parameter`                        |
| Probability      | `probability`, `likelihood`, `risk_probability`, `confidence_level`, `significance_level`         |
| Relationship     | `correlation_coefficient`, `regression_coefficient`, `covariance`, `coefficient_of_determination` |
| Ratios           | `ratio`, `percentage`, `proportion`, `fraction`, `rate`, `index`                                  |
| Counts           | `count`, `sample_size`, `population_size`, `event_count`, `occurrence_count`                      |

# 5. Metric Value Type

A third dimension describes how a metric is represented in the source document.

| Value type      | Description                     | Example                      |
| --------------- | ------------------------------- | ---------------------------- |
| `scalar`        | Single numeric value            | 25 °C                        |
| `range`         | Lower and upper bounds          | 2–8 °C                       |
| `upper_bound`   | Maximum permitted value         | ≤ 5 MPa                      |
| `lower_bound`   | Minimum required value          | ≥ 95%                        |
| `nominal_value` | Designated value                | 220 V                        |
| `tolerance`     | Allowed deviation               | ±0.5 mm                      |
| `interval`      | Numeric interval                | [0, 100]                     |
| `ratio`         | Relationship between quantities | 3:1                          |
| `percentage`    | Value expressed as a percentage | 99.5%                        |
| `count`         | Discrete quantity               | 100 samples                  |
| `boolean`       | Binary property                 | Enabled/disabled             |
| `enumeration`   | One of predefined values        | Low/medium/high              |
| `string`        | Textual value                   | UTF-8                        |
| `vector`        | Multiple numeric components     | [1.0, 2.0, 3.0]              |
| `matrix`        | Two-dimensional array           | 3×3 calibration matrix       |
| `distribution`  | Statistical distribution        | Normal(0, 1)                 |
| `time_series`   | Sequence of time-indexed values | Temperature readings         |
| `formula`       | Mathematical expression         | \\(P = VI\\)                 |
| `table`         | Structured lookup values        | Temperature correction table |
| `curve`         | Functional relationship         | Stress–strain curve          |

These are representation types, not semantic metric kinds. A scalar pressure and a time-series pressure can have the same underlying metric kind.

# 6 Metric Relations

Rather than putting every term into one `metric_kind` enumeration, represent the different dimensions independently.

For example, consider this statement from a measurement standard:

> The maximum permissible error of the thermometer shall not exceed ±0.5 °C under test conditions of 23 ± 2 °C.

This statement contains two metrics.

Metric A: Maximum permissible error
  - Role: compliance_limit
  - Kind: maximum_permissible_error
  - Domain: metrology
  - Value type: tolerance
  - Value: ±0.5 °C
  - Subject: thermometer

Metric B: Test temperature
  - Role: test_condition
  - Kind: temperature
  - Domain: thermal
  - Value: type nominal_with_tolerance
  - Value: 23 ± 2 °C
  - Subject: test environment

The resulting JSON might look like:

```
{
  "metric_name": "maximum permissible error",
  "metric_role": "compliance_limit",
  "metric_kind": "maximum_permissible_error",
  "metric_domain": "metrology",
  "value_type": "tolerance",
  "value": 0.5,
  "unit": "°C",
  "subject": "thermometer",
  "conditions": {
    "temperature": {
      "nominal": 23,
      "tolerance": 2,
      "unit": "°C"
    }
  }
}
```

The `conditions` object is particularly valuable: it preserves the relationship between the permissible error and the temperature at which that requirement applies.

Equally important, the metrics used in a condition should be extracted. 
```text
  A under-condition B
```
