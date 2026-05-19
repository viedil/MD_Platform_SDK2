# Hardware Reference Design

**Version:** 0.9.0  
**Last Updated:** 2025-01-XX  
**Owner:** Hardware Architecture Team

---

## Overview

This document provides hardware reference designs for medical devices based on the Qualcomm QCS8550 platform, including schematics guidance, peripheral selection, and compliance considerations.

---

## System-on-Module (SoM) Architecture

### Recommended SoM: Thundercomm SOM8550 or Equivalent

| Specification | Value |
|---------------|-------|
| **SoC** | Qualcomm QCS8550 (Snapdragon 8 Gen 2) |
| **CPU** | 8x Kryo cores (1x Cortex-X3 @ 3.2GHz, 4x A715, 3x A510) |
| **GPU** | Adreno 740 |
| **NPU** | Hexagon Tensor Accelerator (HTA) |
| **RAM** | 8GB/16GB LPDDR5 |
| **Storage** | 128GB/256GB UFS 4.0 |
| **Dimensions** | 55mm × 55mm × 3.5mm |
| **Connector** | 300-pin board-to-board connector |
| **Operating Temp** | -20°C to +70°C (industrial grade) |

---

## Carrier Board Reference Design

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    CARRIER BOARD                                │
│                                                                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐  │
│  │   Power     │     │    QCS8550   │     │   Medical I/O   │  │
│  │   Management│────▶│     SoM      │◀───▶│   Interface     │  │
│  │   (PMIC)    │     │   (Module)   │     │   Board         │  │
│  └─────────────┘     └──────────────┘     └─────────────────┘  │
│         │                   │ │ │                    │         │
│         │             ┌─────┘ │ └─────┐              │         │
│         ▼             ▼       ▼       ▼              ▼         │
│  ┌─────────────┐ ┌────────┐ ┌────┐ ┌──────────┐ ┌───────────┐  │
│  │ Battery +   │ │ Display│ │USB │ │Ethernet  │ │ Analog    │  │
│  │ Charging    │ │ (MIPI) │ │3.2 │ │(GbE/RGMII)│ │ Front End │  │
│  └─────────────┘ └────────┘ └────┘ └──────────┘ └───────────┘  │
│                                                                 │
│  ┌─────────────┐ ┌────────┐ ┌────┐ ┌──────────┐                │
│  │ WiFi 6E +   │ │ Audio  │ │GPIO│ │ Security │                │
│  │ BT 5.3      │ │ (I2S)  │ │    │ │ (HSM/TPM)│                │
│  └─────────────┘ └────────┘ └────┘ └──────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Power Subsystem

### Power Requirements

| Rail | Voltage | Max Current | Notes |
|------|---------|-------------|-------|
| VDD_CORE | 0.85V | 8A | CPU/GPU core (PMIC internal) |
| VDD_DDR | 1.1V | 3A | LPDDR5 memory |
| VDD_IO | 1.8V/3.3V | 2A | Digital I/O |
| VDISP | 3.3V/5.5V | 1.5A | Display backlight |
| VANALOG | 3.3V | 500mA | Analog sensors (low noise) |
| VUSB | 5V | 3A | USB host/peripheral |
| VETH | 3.3V | 500mA | Ethernet PHY |

### Recommended PMIC

**Primary:** Qualcomm PMX75 (integrated with QCS8550)  
**Secondary:** Texas Instruments TPS6521903 (auxiliary rails)

### Battery Backup

| Specification | Recommendation |
|---------------|----------------|
| **Chemistry** | Li-ion or LiFePO4 |
| **Capacity** | 5000mAh minimum (≥4 hours runtime) |
| **BMS** | TI BQ40Z50-R2 (fuel gauge + protection) |
| **Charging** | QC 4.0+ fast charging (up to 45W) |
| **Hot Swap** | Dual battery support for continuous operation |

### Power Sequencing

Critical sequence for reliable boot:
```
1. VDD_IO (1.8V) → stable
2. VDD_DDR (1.1V) → +5ms delay
3. PMIC enable → internal rails sequence automatically
4. VDISP → after SoC initialization
5. Peripheral rails → as needed
```

Total boot time target: <3 seconds to kernel start

---

## Display Interface

### Primary Display (Medical Grade)

| Parameter | Specification |
|-----------|---------------|
| **Interface** | MIPI DSI (4 lanes) |
| **Resolution** | 1920×1200 or 2560×1600 |
| **Size** | 10.1" to 15.6" |
| **Brightness** | ≥500 nits (indoor), ≥1000 nits (outdoor) |
| **Touch** | Projected capacitive (10-point multi-touch) |
| **Compliance** | IEC 60601-1 (leakage current <10μA) |

### Recommended Panels

| Vendor | Model | Size | Resolution | Notes |
|--------|-------|------|------------|-------|
| Innolux | N156HCE-GN1 | 15.6" | 1920×1080 | Medical grade, anti-glare |
| BOE | NV133FHM-N61 | 13.3" | 1920×1080 | Low blue light |
| AUO | G156HAN01 | 15.6" | 1920×1080 | High brightness (1000 nits) |

### Touch Controller

- **Recommended:** Goodix GT9286 or Microchip MXT144E
- **Interface:** I2C
- **Glove Support:** Yes (medical environment)
- **Stylus Support:** Optional (1mm precision)

---

## Medical I/O Interface Board

### Analog Front End (AFE)

| Signal Type | AFE Chip | Channels | Resolution | Sampling Rate |
|-------------|----------|----------|------------|---------------|
| **ECG** | TI ADS1298R | 8 | 24-bit | 250 SPS - 32 kSPS |
| **EEG** | TI ADS1299 | 8 | 24-bit | 250 SPS - 16 kSPS |
| **SpO2** | Maxim MAX86141 | 1 | 18-bit | 100 SPS |
| **Blood Pressure** | TE Connectivity pressure sensor | 1 | 24-bit | 100 SPS |
| **Temperature** | TI TMP117 | 4 | 16-bit | 1 SPS |

### Isolation Requirements

| Interface | Isolation Method | Rating |
|-----------|------------------|--------|
| Patient-connected inputs | Optocoupler + isolation amplifier | 4kV RMS (IEC 60601-1) |
| Ethernet | Transformer isolation | 2.5kV RMS |
| USB | Digital isolator (ISO7741) | 5kV RMS |
| RS-232/485 | ISO1540 bidirectional isolator | 2.5kV RMS |

### Connector Types (Medical Grade)

| Signal | Connector | Locking Mechanism |
|--------|-----------|-------------------|
| ECG leads | DIN 42-802 (standard 10-pin) | Screw lock |
| SpO2 probe | DB9 female | Bayonet |
| Blood pressure cuff | Hirose DF13-4P | Friction lock |
| USB 3.0 | USB-A or USB-C | Standard |
| Ethernet | RJ45 with magnetics | Standard |

---

## Connectivity

### Wireless

| Technology | Module | Certification |
|------------|--------|---------------|
| **WiFi 6E** | Qualcomm WCN6856 (integrated) | FCC, CE, IC |
| **Bluetooth 5.3** | Qualcomm WCN6856 (integrated) | FCC, CE, IC |
| **Cellular (optional)** | Quectel EM12-G (LTE Cat-12) | PTCRB, GCF |
| **GNSS** | u-blox NEO-M9N | N/A |

### Wired

| Interface | Controller | Speed | Notes |
|-----------|------------|-------|-------|
| **Ethernet** | Intel I210 or Realtek RTL8125 | 1 Gbps | RGMII interface |
| **USB 3.2** | Integrated in QCS8550 | 10 Gbps | 2x Type-A, 1x Type-C |
| **CAN FD** | Microchip MCP2517FD | 5 Mbps | Automotive/medical devices |
| **RS-232** | FTDI FT2232H | 3 Mbps | Legacy device support |

---

## Security Hardware

### Trusted Platform Module (TPM)

| Option | Part | Interface | Notes |
|--------|------|-----------|-------|
| **Discrete TPM** | Infineon SLB9670 | SPI | CC EAL4+ certified |
| **Integrated HSM** | NXP SE050C | I2C | EdgeLock secure element |
| **Qualcomm TEE** | QSEE (in QCS8550) | Internal | TrustZone-based |

### Secure Boot Chain

```
BootROM (immutable) 
    ↓ verify AHAB signature
BL31 (ARM Trusted Firmware)
    ↓ verify U-Boot signature
U-Boot
    ↓ verify Kernel + DTB signature
Linux Kernel (signed FIT image)
    ↓ verify rootfs hash
Root Filesystem (dm-verity protected)
```

---

## Thermal Management

### Thermal Design Power (TDP)

| Component | TDP | Cooling Solution |
|-----------|-----|------------------|
| QCS8550 SoC | 7W (sustained), 10W (peak) | Passive heatsink + thermal pad |
| Display | 5W (backlight) | Metal chassis conduction |
| Total System | 15W typical | Fanless design target |

### Thermal Specifications

| Parameter | Value |
|-----------|-------|
| **Operating Temperature** | 0°C to +40°C (clinical), -10°C to +50°C (transport) |
| **Storage Temperature** | -20°C to +60°C |
| **Junction Temperature (Tj)** | <105°C (max) |
| **Case Temperature** | <50°C (touch-safe per IEC 60601-1) |

### Recommended Heatsink

- **Material:** Aluminum 6061-T6 or copper vapor chamber
- **Thermal Resistance:** <2°C/W (junction-to-ambient)
- **Mounting:** Spring-loaded screws (even pressure)
- **TIM:** Gap pad (Bergquist Sil-Pad 2000 or equivalent)

---

## EMC/EMI Compliance

### Target Standards

| Standard | Description | Class |
|----------|-------------|-------|
| **IEC 60601-1-2** | Medical EMC immunity/emissions | Class B |
| **FCC Part 15** | RF emissions (unintentional radiator) | Class B |
| **EN 55032** | Multimedia equipment emissions | Class B |
| **IEC 61000-4-x** | Immunity test suite | Level 3-4 |

### Design Guidelines

1. **Grounding:** Single-point ground for analog, multipoint for digital
2. **Shielding:** Metal enclosure with conductive gaskets
3. **Filtering:** Ferrite beads on all cables, common-mode chokes
4. **PCB Stack-up:** Minimum 8 layers with dedicated ground planes
5. **Clock Distribution:** Spread spectrum clocking to reduce peaks

---

## Mechanical Considerations

### Enclosure

| Requirement | Specification |
|-------------|---------------|
| **Material** | ABS+PC (UL94 V-0 flame retardant) or aluminum |
| **IP Rating** | IP54 minimum (splash resistant) |
| **Ingress Protection** | Sealed ports with medical-grade caps |
| **Cleaning** | Compatible with hospital disinfectants (bleach, alcohol, quaternary ammonium) |
| **Drop Test** | 0.75m onto concrete (IEC 60601-1) |

### Mounting Options

- VESA 75/100 (wall mount, cart mount)
- Pole mount (OR boom arm compatible)
- Desktop stand (adjustable tilt)

---

## Bill of Materials (Reference)

| Category | Estimated Cost (1k units) |
|----------|---------------------------|
| QCS8550 SoM | $180 - $250 |
| Carrier Board PCB + Components | $80 - $120 |
| Display Assembly | $60 - $150 |
| Battery + BMS | $25 - $40 |
| Enclosure + Mechanics | $30 - $50 |
| Medical I/O Board | $50 - $100 |
| **Total BOM** | **$425 - $710** |

---

## Compliance Checklist

| Certification | Status | Notes |
|---------------|--------|-------|
| **FCC** | Required | Intentional + unintentional radiator |
| **CE Mark** | Required | RED, EMC, LVD directives |
| **IEC 60601-1** | Required | Electrical safety |
| **IEC 60601-1-2** | Required | EMC |
| **ISO 10993** | If patient contact | Biocompatibility |
| **RoHS** | Required | Hazardous substances |
| **REACH** | Required | Chemical registration |

---

## Development Boards

### Evaluation Kit

| Item | Part Number | Supplier |
|------|-------------|----------|
| QCS8550 Development Kit | Thundercomm RB5 Plus | Thundercomm |
| Carrier Board Reference | Custom design (this doc) | In-house/CM |
| Display Module | Innolux N156HCE-GN1 | Innolux |
| AFE Daughter Board | TI ADS1298RECGFE-PDK | Texas Instruments |

### Debug Interfaces

| Interface | Connector | Purpose |
|-----------|-----------|---------|
| UART | 4-pin header (1.27mm) | Console output |
| JTAG | 10-pin ARM connector | CPU debug |
| SWD | 6-pin Cortex connector | Trace |
| I2C/SPI | Test points | Peripheral debug |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.9.0 | 2025-01-XX | Initial hardware reference design |

---

**Note:** This reference design is a starting point. Final product requires customization based on specific use case, regulatory requirements, and manufacturing partner capabilities. Engage with qualified medical device design consultants for production designs.
