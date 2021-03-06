
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity VGA_Controller is
	port(
		rst   : in std_logic;
		clk   : in std_logic;
				
		gfx_wren : in std_logic;
		gfx_data : in std_logic_vector(11 downto 0);
		gfx_addr : in std_logic_vector(16 downto 0);

		flip_req : in std_logic;
		flip_ack : out std_logic;
		
		VGA_R 		: out std_logic_vector(7 downto 0);
		VGA_G 		: out std_logic_vector(7 downto 0);
		VGA_B 		: out std_logic_vector(7 downto 0);
		VGA_BLANK_N : out std_logic;
		VGA_SYNC_N  : out std_logic; 
		VGA_HS      : out std_logic;
		VGA_VS      : out std_logic;
		VGA_CLK     : out std_logic
	);
end VGA_Controller;

architecture behv of VGA_Controller is
	component PLL_VGA is
		port
		(
			areset : in std_logic;
			inclk0 : in std_logic;
			c0		 : out std_logic 
		);
	end component;
	component VGA_Sync is
		port
		(
			rst : in std_logic;
			clk : in std_logic;
			
			blank_n : out std_logic;
			hs : out std_logic;
			vs : out std_logic
		);
	end component;
	component RAM_VIDEO_PAGE is
		port
		(
			data	    : in std_logic_vector(11 downto 0);
			rdaddress : in std_logic_vector (16 downto 0);
			rdclock	 : in std_logic;
			wraddress : in std_logic_vector (16 downto 0);
			wrclock	 : in std_logic;
			wren		 : in std_logic;
			q		    : out std_logic_vector (11 downto 0)
		);
	end component;

	constant BG_COL : std_logic_vector(11 downto 0) := "000000000001";
	
	constant disp_left  : integer := 160;
	constant disp_hi    : integer := 120;
	constant disp_lo    : integer := 360;
	constant disp_right : integer := 480;
	constant video_size : integer := 76800;
	
	constant screen_w : integer := 640;
	constant screen_h : integer := 480;
	
	signal vga_c_clk : std_logic;
	signal w_hs : std_logic;
	signal w_vs : std_logic;
	signal w_blank_n : std_logic;
	
	signal video_scan : integer range 0 to 76799;
	signal h_scan : integer range 0 to 639;
	signal v_scan : integer range 0 to 479;
	
	signal has_flipped : std_logic;
	
	signal cur_page : std_logic_vector(2 downto 0);
	signal in_range  : std_logic_vector(2 downto 0);	
	
	signal pxl_vid0 : std_logic_vector(11 downto 0);
	signal pxl_vid1 : std_logic_vector(11 downto 0);
	signal pxl_color_final : std_logic_vector(11 downto 0);
	signal pxl_color_video : std_logic_vector(11 downto 0);
	
	signal v_addr : std_logic_vector(16 downto 0);
	signal write_page_0 : std_logic;
	signal write_page_1 : std_logic;
	
	begin
		pll0 : PLL_VGA port map(rst, clk, vga_c_clk);
		sync0 : VGA_Sync port map (rst, vga_c_clk, w_blank_n, w_hs, w_vs);
		  
		v_addr <= std_logic_vector(to_unsigned(video_scan, 17));
		
		write_page_0 <= (not cur_page(2)) and gfx_wren;
		write_page_1 <= cur_page(2) and gfx_wren;
		  
		vga_buffer_0 : RAM_VIDEO_PAGE port map (gfx_data, v_addr, vga_c_clk, 
															 gfx_addr, clk, write_page_0, pxl_vid0);
		vga_buffer_1 : RAM_VIDEO_PAGE port map (gfx_data, v_addr, vga_c_clk, 
															 gfx_addr, clk, write_page_1, pxl_vid1);
				
		process(vga_c_clk, rst)
			begin
				if rst='1' then
					video_scan <= 0;
					cur_page <= "000";
					h_scan <= 0;
					v_scan <= 0;
					in_range <= "000";
					has_flipped <= '0';
					flip_ack <= '0';
				else
					if vga_c_clk'event and vga_c_clk='1' then
						if (h_scan >= disp_left) and (h_scan < disp_right) and 
							(v_scan >= disp_hi) and (v_scan < disp_lo) then
							if video_scan = (video_size - 1) then
								video_scan <= 0;
							else
								video_scan <= video_scan + 1;
							end if;
							in_range(0) <= '1';
						else
							in_range(0) <= '0';
						end if;
						
						if w_blank_n = '1' then
							if h_scan /= (screen_w - 1) then
								h_scan <= h_scan + 1;
								flip_ack <= '0';
								if flip_req = '0' then 
									has_flipped <= '0';
								end if;
							else
								h_scan <= 0;
								if v_scan /= (screen_h - 1) then
									v_scan <= v_scan + 1;
								else
									v_scan <= 0;
									if (has_flipped = '0') and (flip_req = '1') then
										has_flipped <= '1';
										flip_ack <= '1';
										if cur_page(0) = '0' then
											cur_page(0) <= '1';
										else
											cur_page(0) <= '0';
										end if;
									end if;
								end if;
							end if;
						end if;
						VGA_BLANK_N <= w_blank_n;
						VGA_HS <= w_hs;
						VGA_VS <= w_vs;
						cur_page(1) <= cur_page(0);
						cur_page(2) <= cur_page(1);
						in_range(1) <= in_range(0);
						in_range(2) <= in_range(1);
					end if;
				end if;
		end process;
		
		pxl_color_video <= pxl_vid0 when (cur_page(2) = '0') else pxl_vid1;
		pxl_color_final <= BG_COL when (in_range(2) = '0') else pxl_color_video;
		
		VGA_R <= pxl_color_final(11 downto 8) & "0000";		
		VGA_G <= pxl_color_final(7 downto 4) & "0000"; 		
		VGA_B <= pxl_color_final(3 downto 0) & "0000";
		VGA_CLK <= vga_c_clk;
		VGA_SYNC_N <= '1';

end behv;