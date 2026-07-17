---	output_counter: counts spikes from the 10 output neurons across the full time window ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity output_counter is

  generic (
    T : integer := 16 -- Number of time steps for inference
  );

  port (
    clk : in std_logic;
    rst : in std_logic;

    -- Each output neuron's spike at the current time step.
    input_spike       : in std_logic;
    input_spike_valid : in std_logic; -- Counters should wait for this signal to start counting for 1 cycle, right after output neurons give their spikes.
    reset_counter     : in std_logic; -- Signal coming from the layer_controller stating that we are about to start with a new sample and the counter should be reset.
    spike_count       : out integer range 0 to T -- Output: spike count for each of the 10 output neurons across the full time window. Each neuron can fire at most once per time step, so the max count is T.
  );

end output_counter;

architecture Behavioral of output_counter is

  signal count : integer range 0 to T := 0; -- Internal signal to keep track of the spike count for the current neuron.

begin

  process (clk, rst)
  begin

    if rst = '1' then
      count <= 0;

    elsif rising_edge(clk) then

      if reset_counter /= '1' then

        if input_spike = '1' and input_spike_valid = '1' then
          count <= count + 1; -- Increment the count for the current neuron when it fires.
        end if;

      else
        count <= 0; -- Reset the counter

      end if;

    end if;

  end process;

  -- Update the output spike count for the current neuron at each clock cycle. This will hold the final count after T time steps.
  spike_count <= count;

end Behavioral;