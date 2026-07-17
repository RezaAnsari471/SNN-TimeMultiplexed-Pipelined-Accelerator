# =============================================================================
# CLOCK CONSTRAINT
# =============================================================================
# The virtual timing clock tree
create_clock -period 6.000 -name sys_clk [get_ports clk]

# Pin placement and voltage standard for the clock pin
set_property PACKAGE_PIN P16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# To bypass the clock skew error
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_IBUF]
# =============================================================================
# INPUT PUSH BUTTONS (Resets and Switches)
# =============================================================================
# CPU Reset Button (Pin U4) - Uses 1.5V logic bank
set_property PACKAGE_PIN U4 [get_ports rst]
set_property IOSTANDARD LVCMOS15 [get_ports rst]

# Start Button (Center Directional Switch Pin U6) - Uses 1.5V logic bank
set_property PACKAGE_PIN U6 [get_ports start]
set_property IOSTANDARD LVCMOS15 [get_ports start]

# =============================================================================
# OUTPUT INDICATORS (Onboard LEDs)
# =============================================================================
# Prediction Ready Flag -> Maps to User LED 0 (Pin M26)
set_property PACKAGE_PIN M26 [get_ports prediction_ready]
set_property IOSTANDARD LVCMOS33 [get_ports prediction_ready]

# Predicted Label Bits (0 to 3) -> Maps to User LEDs
set_property PACKAGE_PIN T24 [get_ports {predicted_label[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {predicted_label[0]}]

set_property PACKAGE_PIN T25 [get_ports {predicted_label[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {predicted_label[1]}]

set_property PACKAGE_PIN R26 [get_ports {predicted_label[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {predicted_label[2]}]

set_property PACKAGE_PIN M22 [get_ports {predicted_label[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {predicted_label[3]}]
