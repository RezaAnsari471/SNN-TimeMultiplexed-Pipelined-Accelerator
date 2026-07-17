--- Module for the argmax_unit: selects predicted digit from the 10 output counters ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity argmax_unit is

  port (
    clk : in std_logic;
    rst : in std_logic;

    -- Array of spike counts from the 10 output neurons. First element contains the spike_count of output_neuron_0 and so on.
    spike_counts : in integer_vector(0 to 9);

    -- Gives the index of the neuron with the highest spike count.
    predicted_label : out integer range 0 to 10 := 10; -- Choosing number 10 as the out-of-bound (0 - 9) uninitalized default value.

    -- Signal from layer_controller telling argmax_unit to calculate the predicted label. It should arrive after t = T.
    calculate_argmax : in std_logic;
    prediction_ready : out std_logic; -- Signal to the layer controller and top-level to indicate that the predicted label is ready.

    -- Membrane potentials to select the neuron with highest potential in case all spike counts are zero
    v_from_output_neurons : in integer_vector(0 to 9)

  );

end argmax_unit;

architecture Behavioral of argmax_unit is

  -- State encoding for the FSM
  type state_type is (IDLE, COMPARE_SPIKE_COUNTS, COMPARE_MEMBRANE_POTENTIALS, REPORT_PREDICTED_LABEL, WAIT_FOR_RESET);
  signal current_state : state_type := IDLE;

begin

  process (clk, rst)
    variable var_predicted_label   : integer range 0 to 9  := 0;
    variable output_neuron_counter : integer range 1 to 10 := 1; -- to loop through output neurons when comparing spike counts and membrane potentials.
  begin

    if rst = '1' then
      predicted_label <= 10;
      current_state   <= IDLE;

    elsif rising_edge(clk) then

      case current_state is
          ----------------------------------------------------------------------------------------------------
        when IDLE =>

          prediction_ready <= '0';
          var_predicted_label   := 0; -- reset variable to start comparison from the first output neuron.
          output_neuron_counter := 1; -- reset counter to start comparison from the second output neuron since we initialize var_predicted_label with the first neuron's values.
          if calculate_argmax = '1' then
            current_state <= COMPARE_SPIKE_COUNTS;
          end if;
          ----------------------------------------------------------------------------------------------------
        when COMPARE_SPIKE_COUNTS =>

          -- 10 cycles compare spike counts
          if output_neuron_counter < 10 then
            if spike_counts(output_neuron_counter) > spike_counts(var_predicted_label) then
              var_predicted_label := output_neuron_counter;
            end if;
            output_neuron_counter := output_neuron_counter + 1;
          end if;

          if output_neuron_counter = 10 then -- After 10 clock cycles
            -- If no spikes, use final membrane potential as tie-breaker.
            if spike_counts(var_predicted_label) = 0 then -- if any neuron spiked even once, spike_counts(var_predicted_label) will be greater than zero.
              output_neuron_counter := 1; -- reset counter to loop through output neurons again, this time comparing membrane potentials.
              current_state <= COMPARE_MEMBRANE_POTENTIALS;
            else
              current_state <= REPORT_PREDICTED_LABEL;
            end if;
          end if;
          ----------------------------------------------------------------------------------------------------
        when COMPARE_MEMBRANE_POTENTIALS =>

          -- 10 cycles compare membrane potentials
          if output_neuron_counter < 10 then
            if v_from_output_neurons(output_neuron_counter) > v_from_output_neurons(var_predicted_label) then
              var_predicted_label := output_neuron_counter;
            end if;
            output_neuron_counter := output_neuron_counter + 1;
          end if;

          -- After 10 clock cycles
          if output_neuron_counter = 10 then
            current_state <= REPORT_PREDICTED_LABEL;
          end if;
          ----------------------------------------------------------------------------------------------------
        when REPORT_PREDICTED_LABEL =>

          predicted_label  <= var_predicted_label;
          prediction_ready <= '1'; -- Signal that a new prediction is ready.
          current_state    <= WAIT_FOR_RESET; -- Wait 1 clk cycle so the controller gets out of ARGMAX_COMPUTING and calculate_argmax goes back to '0' before transitioning back to IDLE.
          ----------------------------------------------------------------------------------------------------
        when WAIT_FOR_RESET =>

          prediction_ready <= '0'; -- Instantly drop the flag so the testbench only reads it once
          current_state <= IDLE;
          ----------------------------------------------------------------------------------------------------
      end case;

    end if;
  end process;
end Behavioral;