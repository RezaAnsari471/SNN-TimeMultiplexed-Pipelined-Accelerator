--- Module for a single Leaky Integrate-and-Fire (LIF) neuron: membrane register, leak, threshold comparison, reset, spike output ---
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity lif_neuron is
  generic (
    theta      : integer;
    leak_shift : integer
  );
  port (
    clk          : in std_logic;
    rst          : in std_logic;
    I_syn        : in std_logic_vector(31 downto 0); -- Synaptic input current (32-bit)
    en_lif       : in std_logic; -- Enable signal from controller
    rst_V        : in std_logic; -- Reset membrane potentials signal from controller
    output_spike : out std_logic; -- Output spike of the neuron
    V_out        : out integer -- membrane potential to argmax unit as tie-breaker
  );
end lif_neuron;

architecture Behavioral of lif_neuron is

  -- Allocate 32 bits for the membrane potential to prevent overflow
  signal V : signed(31 downto 0) := (others => '0');

begin
  --- Process to update the membrane potential and generate spikes
  process (clk, rst)
    variable V_next : signed(31 downto 0) := (others => '0');
  begin
    if rst = '1' then
      V            <= (others => '0');
      output_spike <= '0';

    elsif rising_edge(clk) then

      -- Check for global sample transition reset first
      if rst_V = '1' then
        V            <= (others => '0');
        output_spike <= '0'; -- Ensure spike is low during sample reset

        -- If this specific layer is active, evaluate updates and firing
      elsif en_lif = '1' then

        -- Update membrane potential V_next = V - (V >> leak_shift) + I_syn
        V_next := V - shift_right(V, leak_shift) + signed(I_syn);

        -- Check if the neuron fires (V >= THETA)
        if V_next >= to_signed(theta, 31) then
          output_spike <= '1'; -- Spike high
          V            <= (others => '0'); -- Reset membrane potential after firing
        else
          output_spike <= '0'; -- Explicitly clear spike if threshold isn't met
          V            <= V_next; -- Update membrane potential for the next cycle
        end if;
      end if;
    end if;
  end process;

  V_out <= to_integer(V);

end Behavioral;