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

    -- Membrane potentials to select the neuron with highest potential in case all spike counts are zero
    v_from_output_neurons : in integer_vector(0 to 9)

  );

end argmax_unit;

architecture Behavioral of argmax_unit is
begin

  process (clk, rst)
    variable var_predicted_label : integer range 0 to 9 := 0;

  begin

    if rst = '1' then
      predicted_label <= 10;

    elsif rising_edge(clk) then
      if calculate_argmax = '1' then

        -- Loop through the spike_counts array and find the index of the neuron with the highest spike count. The predicted number always starts with 0.
        var_predicted_label := 0;
        for i in 1 to 9 loop
          if spike_counts(i) > spike_counts(var_predicted_label) then
            var_predicted_label := i;
          end if;
        end loop;

        -- If no spikes, use final membrane potential as tie-breaker.
        if spike_counts(var_predicted_label) = 0 then -- if any neuron spiked even once, spike_counts(var_predicted_label) will be greater than zero.

          for i in 1 to 9 loop
            if v_from_output_neurons(i) > v_from_output_neurons(var_predicted_label) then -- var_predicted_label is 0 initially.
              var_predicted_label := i;
            end if;
          end loop;
        end if;

        -- Only update the predicted_label signal if calculate_argmax = '1', otherwise don't update it.
        predicted_label <= var_predicted_label;
      end if;

    end if;
  end process;
end Behavioral;