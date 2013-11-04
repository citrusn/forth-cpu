--------------------------------------------------------------------------------- 
--! @file top_level.vhd
--! @brief This file is the top level of the project.
--!  It presents an interface between the CPU,
--!  RAM, and all the I/O modules.
--!
--! @author     Richard James Howe.
--! @copyright  Copyright 2013 Richard James Howe.
--! @license    LGPL    
--! @email      howe.r.j.89@gmail.com
--------------------------------------------------------------------------------- 

library ieee,work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_level is
  port
  (
-- pragma translate_off
-- synthesis translate_off
-- synopsys translate_off

  -- This should be removed once testing is done in the interests of
  -- portability.
   sim_irq:   in  std_logic;
   sim_irc:   in  std_logic_vector(3 downto 0);
-- synopsys translate_on
-- synthesis translate_on
-- pragma translate_on

    clk:      in  std_logic                    :=      'X';  -- clock
    -- Buttons
    btnu:     in  std_logic                    :=      'X';  -- button up
    btnd:     in  std_logic                    :=      'X';  -- button down
    btnc:     in  std_logic                    :=      'X';  -- button centre
    btnl:     in  std_logic                    :=      'X';  -- button left
    btnr:     in  std_logic                    :=      'X';  -- button right
    -- Switches
    sw:       in  std_logic_vector(7 downto 0) :=      (others => 'X'); -- switches
    -- Simple LED outputs
    an:       out std_logic_vector(3 downto 0) :=      (others => '0'); -- anodes   7 segment display
    ka:       out std_logic_vector(7 downto 0) :=      (others => '0'); -- kathodes 7 segment display
    ld:       out std_logic_vector(7 downto 0) :=      (others => '0'); -- leds
    -- UART
    rx:       in  std_logic                    :=      'X';  -- uart rx 
    tx:       out std_logic                    :=      '0';  -- uart tx
    -- VGA
    red:      out std_logic_vector(2 downto 0) :=      (others => '0'); 
    green:    out std_logic_vector(2 downto 0) :=      (others => '0'); 
    blue:     out std_logic_vector(1 downto 0) :=      (others => '0'); 
    hsync:    out std_logic                    :=      '0';
    vsync:    out std_logic                    :=      '0';
    -- PWM from timer
    gpt0_q:   out std_logic                    :=      '0';
    gpt0_nq:  out std_logic                    :=      '0'

  );
end;

architecture behav of top_level is
  -- System constants
  constant baud_rate:               positive := 115200;
  constant clock_frequency:         positive := 100000000;
  -- Signals
  signal  rst:                      std_logic := '0';
  -- CPU H2 IO interface signals.
  signal  cpu_io_wr:                std_logic := '0';
  signal  cpu_io_din:               std_logic_vector(15 downto 0):= (others => '0');
  signal  cpu_io_dout:              std_logic_vector(15 downto 0):= (others => '0');
  signal  cpu_io_daddr:             std_logic_vector(15 downto 0):= (others => '0');
  -- CPU H2 Interrupts
  signal  cpu_irq:                  std_logic:= '0';
  signal  cpu_irc:                  std_logic_vector(3 downto 0):= (others => '0');

  -- VGA interface signals
  signal  clk25MHz:                 std_logic:= '0';
  signal  clk50MHz:                 std_logic:= '0';
  -- Basic IO register
  ---- LEDs/Switches
  signal  an_c,an_n:                std_logic_vector(3 downto 0):=  (others => '0');
  signal  ka_c,ka_n:                std_logic_vector(7 downto 0):=  (others => '0');
  signal  ld_c,ld_n:                std_logic_vector(7 downto 0):=  (others => '0');
  ---- VGA

  signal  crx_we:           std_logic :=  '0';
  signal  cry_we:           std_logic :=  '0';
  signal  ctl_we:           std_logic :=  '0';

  signal  crx:           std_logic_vector(6 downto 0):=  (others => '0');
  signal  cry:           std_logic_vector(5 downto 0):=  (others => '0');
  signal  ctl:           std_logic_vector(6 downto 0):=  (others => '0');
  signal  vga_we_ram:           std_logic :=  '0';
  signal  vga_a_we:           std_logic :=  '0';
  signal  vga_d_we:           std_logic :=  '0';
  signal  vga_addr:      std_logic_vector(11 downto 0):= (others => '0');
  signal  vga_dout:      std_logic_vector(7 downto 0) := (others => '0');
  signal  vga_din:       std_logic_vector(7 downto 0) := (others => '0');

  ---- UART
  signal  uart_din_c, uart_din_n:   std_logic_vector(7 downto 0) := (others => '0');
  signal  ack_din_c, ack_din_n:     std_logic:= '0';
  signal  uart_dout_c, uart_dout_n: std_logic_vector(7 downto 0):= (others => '0');
  signal  stb_dout_c, stb_dout_n:   std_logic:= '0';
  signal  uart_din, uart_dout:      std_logic_vector(7 downto 0):= (others => '0');
  signal  stb_din, stb_dout:        std_logic:= '0';
  signal  ack_din, ack_dout:        std_logic:= '0';
  signal  tx_uart, rx_uart,rx_sync: std_logic:= '0';

  signal  gpt0_timer_reset:  std_logic := '0';
  signal  gpt0_ctr_r_we:     std_logic := '0';               
  signal  gpt0_comp1_r_we:   std_logic := '0';                
  signal  gpt0_comp2_r_we:   std_logic := '0';                 
  signal  gpt0_load1_r_we:   std_logic := '0';                  
  signal  gpt0_load2_r_we:   std_logic := '0';                   
  signal  gpt0_load_s_we:    std_logic := '0';                   
  signal  gpt0_ctr_r:        std_logic_vector(15 downto 0) := (others =>'0');
  signal  gpt0_comp1_r:      std_logic_vector(15 downto 0) := (others =>'0');
  signal  gpt0_comp2_r:      std_logic_vector(15 downto 0) := (others =>'0');
  signal  gpt0_load1_r:      std_logic_vector(15 downto 0) := (others =>'0');
  signal  gpt0_load2_r:      std_logic_vector(15 downto 0) := (others =>'0'); 
  signal  gpt0_load_s:       std_logic_vector(15 downto 0) := (others =>'0');
  signal  gpt0_irq_comp1:    std_logic;                    
  signal  gpt0_irq_comp2:    std_logic;                    
  signal  gpt0_q_internal:   std_logic;                    
  signal  gpt0_nq_internal:  std_logic;

begin
------- Output assignments (Not in a process) ---------------------------------
  rst   <=  '0';
-------------------------------------------------------------------------------
-- The Main components
-------------------------------------------------------------------------------

-- pragma translate_off
-- synthesis translate_off
-- synopsys translate_off

  -- This should be removed once testing is done in the interests of
  -- portability.
  cpu_irq <= sim_irq;
  cpu_irc <= sim_irc;
-- synopsys translate_on
-- synthesis translate_on
-- pragma translate_on


  cpu_instance: entity work.cpu
  port map(
    clk       => clk,
    rst       => rst,

    cpu_wr    => cpu_io_wr,
    cpu_din   => cpu_io_din,
    cpu_dout  => cpu_io_dout,
    cpu_daddr => cpu_io_daddr,

    cpu_irq   => cpu_irq,
    cpu_irc   => cpu_irc
  );

-------------------------------------------------------------------------------
-- IO
-------------------------------------------------------------------------------

   -- Xilinx Application Note:
   -- It seems like it buffers the clock correctly here, so no need to
   -- use a DCM.
   ---- Clock divider /2. 
   clk50MHz <= '0' when rst = '1' else
        not clk50MHz when rising_edge(clk);

   ---- Clock divider /2. Pixel clock is 25MHz
   clk25MHz <= '0' when rst = '1' else
        not clk25MHz when rising_edge(clk50MHz);
   ---- End note.

   io_nextState: process(clk,rst)
   begin
     if rst='1' then
       -- LEDs/Switches
       an_c        <=  (others => '0');
       ka_c        <=  (others => '0');
       ld_c        <=  (others => '0');
       -- UART
       uart_din_c  <=  (others => '0');
       ack_din_c   <=  '0';
       stb_dout_c  <=  '0';
     elsif rising_edge(clk) then
       -- LEDs/Switches
       an_c        <=  an_n;
       ka_c        <=  ka_n;
       ld_c        <=  ld_n;
       -- UART
       uart_din_c  <=  uart_din_n; 
       ack_din_c   <=  ack_din_n;
       uart_dout_c <=  uart_dout_n;
       stb_dout_c  <=  stb_dout_n;
     end if;
   end process;

  io_select: process(
    cpu_io_wr,cpu_io_dout,cpu_io_daddr,
    an_c,ka_c,ld_c,
    sw,rx,btnu,btnd,btnl,btnr,btnc,
    uart_din_c, ack_din_c,
    uart_dout_c, 
    uart_dout, stb_dout, ack_din,
    stb_dout, stb_dout_c, vga_dout,

    gpt0_ctr_r_we ,
    gpt0_comp1_r_we ,
    gpt0_comp2_r_we ,
    gpt0_load1_r_we ,
    gpt0_load2_r_we ,
    gpt0_load_s_we
  )
  begin
    -- Outputs
    an <= an_c;
    ka <= ka_c;
    ld <= ld_c;

    uart_din    <= uart_din_c;
    stb_din     <= '0';
    ack_dout    <= '0';

    -- Register defaults
    an_n <= an_c;
    ka_n <= ka_c;
    ld_n <= ld_c;

    -- VGA
    crx_we <= '0';
    cry_we <= '0';
    ctl_we <= '0';
    crx <= (others => '0');
    cry <= (others => '0');
    ctl <= (others => '0');

    vga_we_ram <= '0';
    vga_a_we <= '0';
    vga_d_we <= '0';
    vga_din <= (others => '0');
    vga_addr <= (others => '0');

    uart_din_n  <=  uart_din_c; 

    -- General Purpose Timer
    gpt0_ctr_r_we <= '0';
    gpt0_comp1_r_we <= '0';
    gpt0_comp2_r_we <= '0';
    gpt0_load1_r_we <= '0';
    gpt0_load2_r_we <= '0';
    gpt0_load_s_we <= '0';

    gpt0_timer_reset <= '0';
    gpt0_ctr_r <= (others => '0');
    gpt0_comp1_r <= (others => '0');
    gpt0_comp2_r <= (others => '0');
    gpt0_load1_r <= (others => '0');
    gpt0_load2_r <= (others => '0');
    gpt0_load_s <= (others => '0');

    if ack_din = '1' then
        ack_din_n <= '1';
    else
        ack_din_n <= ack_din_c;
    end if;

    if stb_dout = '1' then
        stb_dout_n <= '1';
        uart_dout_n <= uart_dout;
        ack_dout <= '1';
    else
        uart_dout_n <=  uart_dout_c;
        stb_dout_n <= stb_dout_c;
    end if;

    cpu_io_din <= (others => '0');

    if cpu_io_wr = '1' then
      -- Write output.
      case cpu_io_daddr(4 downto 0) is
        when "00000" => -- LEDs 7 Segment displays.
          an_n <= cpu_io_dout(3 downto 0);
          ka_n <= cpu_io_dout(15 downto 8);
        when "00001" => -- LEDs, next to switches.
          ld_n <= cpu_io_dout(7 downto 0);
        when "00010" => -- VGA, cursor registers.
          crx_we <= '1';
          cry_we <= '1';
          crx <= cpu_io_dout(6 downto 0);
          cry <= cpu_io_dout(13 downto 8);
        when "00011" => -- VGA, control register.
          ctl_we <= '1';
          ctl <= cpu_io_dout(6 downto 0);
        when "00100" => -- VGA update address register.
          vga_a_we <= '1';
          vga_addr <= cpu_io_dout(11 downto 0);
        when "00101" => -- VGA, update register.
          vga_d_we <= '1';
          vga_din <= cpu_io_dout(7 downto 0);
        when "00110" => -- VGA write RAM write
          vga_we_ram <= '1';
        when "00111" => -- UART write output.
          uart_din_n <= cpu_io_dout(7 downto 0);
        when "01000" => -- UART strobe input.
          stb_din <= '1';
        when "01001" => -- UART acknowledge output.
          ack_dout <= '1';
        when "01010" => 
          gpt0_ctr_r_we <= '1';
          gpt0_ctr_r    <= cpu_io_dout(15 downto 0);
        when "01011" =>
          gpt0_comp1_r_we <= '1';
          gpt0_comp1_r    <= cpu_io_dout(15 downto 0);
        when "01100" =>
          gpt0_comp2_r_we <= '1';
          gpt0_comp2_r    <= cpu_io_dout(15 downto 0);
        when "01101" =>
          gpt0_load1_r_we <= '1';
          gpt0_load1_r    <= cpu_io_dout(15 downto 0);
        when "01110" =>
          gpt0_load2_r_we <= '1';
          gpt0_load2_r    <= cpu_io_dout(15 downto 0);
        when "01111" =>
          gpt0_load_s_we <= '1';
          gpt0_load_s    <= cpu_io_dout(15 downto 0);
        when "10000" =>
          gpt0_timer_reset <= '1';
        when others =>
      end case;
    else
      -- Get input.
      case cpu_io_daddr(3 downto 0) is
        when "0000" => -- Switches, plus direct access to UART bit.
                cpu_io_din <= "0000000000" & rx & btnu & btnd & btnl & btnr & btnc;
        when "0001" => 
                cpu_io_din <= X"00" & sw;
        when "0010" => -- VGA, Read VGA text buffer.
                cpu_io_din <= X"00" & vga_dout;
        when "0011" => -- UART get input.
                cpu_io_din <= X"00" & uart_dout_c;
        when "0100" => -- UART acknowledged input.
                cpu_io_din <= (0 => ack_din_c, others => '0');
                ack_din_n <= '0';
        when "0101" => -- UART strobe output (write output).
                cpu_io_din <= (0 => stb_dout_c, others => '0');
                stb_dout_n <= '0';
        when "0110" => cpu_io_din <= (others => '0');
        when "0111" => cpu_io_din <= (others => '0');
        when "1000" => cpu_io_din <= (others => '0');
        when "1001" => cpu_io_din <= (others => '0');
        when "1010" => cpu_io_din <= (others => '0');
        when "1011" => cpu_io_din <= (others => '0');
        when "1100" => cpu_io_din <= (others => '0');
        when "1101" => cpu_io_din <= (others => '0');
        when "1110" => cpu_io_din <= (others => '0');
        when "1111" => cpu_io_din <= (others => '0');
        when others => cpu_io_din <= (others => '0');
      end case;
    end if;
  end process;

  u_uart: entity work.uart 
  generic map(
    BAUD_RATE => baud_rate,
    CLOCK_FREQUENCY => clock_frequency
  )
  port map(
   clock => clk,
   reset => rst,
   data_stream_in => uart_din,
   data_stream_in_stb => stb_din,
   data_stream_in_ack => ack_din,
   data_stream_out => uart_dout,
   data_stream_out_stb => stb_dout,
   data_stream_out_ack => ack_dout,
   rx => rx_uart,
   tx => tx_uart
  );

  uart_deglitch: process (clk)
  begin
      if rising_edge(clk) then
          rx_sync <= rx;
          rx_uart <= rx_sync;
          tx <= tx_uart;
      end if;
  end process;

  gpt0_q <= gpt0_q_internal;
  gpt0_nq <= gpt0_nq_internal;
  gptimer0_module: entity work.gptimer
  port map(
    clk => clk,
    rst => rst,
    timer_reset => gpt0_timer_reset,
    ctr_r_we => gpt0_ctr_r_we,
    comp1_r_we => gpt0_comp1_r_we,
    comp2_r_we => gpt0_comp2_r_we,
    load1_r_we => gpt0_load1_r_we,
    load2_r_we => gpt0_load2_r_we,
    load_s_we => gpt0_load_s_we,
    ctr_r => gpt0_ctr_r,
    comp1_r => gpt0_comp1_r,
    comp2_r => gpt0_comp2_r,
    load1_r => gpt0_load1_r,
    load2_r => gpt0_load2_r,
    load_s => gpt0_load_s,
    irq_comp1 => gpt0_irq_comp1,
    irq_comp2 => gpt0_irq_comp2,
    Q => gpt0_q_internal,
    NQ => gpt0_nq_internal
          );


  vga_module: entity work.vga_top
  port map(
            clk => clk,
            clk25MHz => clk25MHz,
            rst => rst,
            
            crx_we => crx_we, 
            cry_we => cry_we, 
            ctl_we => ctl_we, 

            crx_oreg => crx, 
            cry_oreg => cry, 
            ctl_oreg => ctl, 

            vga_we_ram => vga_we_ram,
            vga_a_we => vga_a_we,
            vga_d_we => vga_d_we,
            vga_dout => vga_dout,
            vga_din => vga_din,
            vga_addr => vga_addr,

            red => red,  
            green => green,  
            blue => blue,  
            hsync => hsync,  
            vsync => vsync 
  );



-------------------------------------------------------------------------------
end architecture;
