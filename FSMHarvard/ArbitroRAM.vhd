-- ============================================================================
-- Modulo: ArbitroRAM.vhd
-- Descripcion:
--   Arbitro de bus y multiplexor de acceso para la memoria RAM compartida.
--   Asigna prioridad estricta a la unidad de procesamiento FSMHarvard durante
--   ciclos de actualizacion (fsm_busy = '1'). En reposo, cede el direccionamiento
--   al modulo de visualizacion (AdaptadorRAMVistas).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity ArbitroRAM is
    port (
        -- Senal de control de prioridad
        fsm_busy       : in  std_logic;
        
        -- Puerto A: Unidad de control (FSMHarvard - Lectura/Escritura)
        fsm_ram_addr   : in  std_logic_vector(3 downto 0);
        fsm_ram_din    : in  std_logic_vector(7 downto 0);
        fsm_ram_we     : in  std_logic;
        
        -- Puerto B: Unidad de visualizacion (AdaptadorRAMVistas - Solo lectura)
        adap_ram_addr  : in  std_logic_vector(3 downto 0);
        
        -- Interfaz fisica hacia MemoriaRAM
        ram_addr       : out std_logic_vector(3 downto 0);
        ram_din        : out std_logic_vector(7 downto 0);
        ram_we         : out std_logic;
        
        -- Bus de datos de retorno
        ram_dout       : in  std_logic_vector(7 downto 0);
        fsm_ram_dout   : out std_logic_vector(7 downto 0);
        adap_ram_dout  : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of ArbitroRAM is
begin

    -- Arbitraje combinacional con prioridad a la FSM
    ram_addr <= fsm_ram_addr when fsm_busy = '1' else adap_ram_addr;
    ram_din  <= fsm_ram_din;
    ram_we   <= fsm_ram_we when fsm_busy = '1' else '0';
    
    -- Distribucion concurrente del bus de lectura
    fsm_ram_dout  <= ram_dout;
    adap_ram_dout <= ram_dout;
    
end architecture;
