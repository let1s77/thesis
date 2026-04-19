module piece_decoder (
  input logic        clk,
  input logic  [8:0] piece_id,
  input logic  [9:0] H_Count_Value,
  input logic  [9:0] V_Count_Value,
  output logic [3:0] red,
  output logic [3:0] green,
  output logic [3:0] blue
);

logic [255:0] temp_blue, temp_red,temp_green;
logic [10:0] piece_sel;
//256 x 256-bit rom (each 4-bit is 1 color)
piece_rom_red piece_rom_red_u(
  .address(piece_id),
  .clock(clk),
  .q(temp_red)
);

piece_rom_blue piece_rom_blue_u(
  .address(piece_id),
  .clock(clk),
  .q(temp_blue)
);

piece_rom_green piece_rom_green_u(
  .address(piece_id),
  .clock(clk),
  .q(temp_green)
);

assign piece_sel = ((H_Count_Value-1'b1)%10'd8) + ((V_Count_Value+10'd1)%10'd8)*10'd8; // 0..63

always_comb begin
  case(piece_sel)
  10'd0: begin
    red   = temp_red   [3:0];
    blue  = temp_blue  [3:0];
    green = temp_green [3:0];
  end
  10'd1: begin
    red   = temp_red   [7:4];
    blue  = temp_blue  [7:4];
    green = temp_green [7:4];
  end
  10'd2: begin
    red   = temp_red   [11:8];
    blue  = temp_blue  [11:8];
    green = temp_green [11:8];
  end
  10'd3: begin
    red   = temp_red   [15:12];
    blue  = temp_blue  [15:12];
    green = temp_green [15:12];
  end
  10'd4: begin
    red   = temp_red   [19:16];
    blue  = temp_blue  [19:16];
    green = temp_green [19:16];
  end
  10'd5: begin
    red   = temp_red   [23:20];
    blue  = temp_blue  [23:20];
    green = temp_green [23:20];
  end
  10'd6: begin
    red   = temp_red   [27:24];
    blue  = temp_blue  [27:24];
    green = temp_green [27:24];
  end
  10'd7: begin
    red   = temp_red   [31:28];
    blue  = temp_blue  [31:28];
    green = temp_green [31:28];
  end
  10'd8: begin
    red   = temp_red   [35:32];
    blue  = temp_blue  [35:32];
    green = temp_green [35:32];
  end
  10'd9: begin
    red   = temp_red   [39:36];
    blue  = temp_blue  [39:36];
    green = temp_green [39:36];
  end
  10'd10: begin
    red   = temp_red   [43:40];
    blue  = temp_blue  [43:40];
    green = temp_green [43:40];
  end
  10'd11: begin
    red   = temp_red   [47:44];
    blue  = temp_blue  [47:44];
    green = temp_green [47:44];
  end
  10'd12: begin
    red   = temp_red   [51:48];
    blue  = temp_blue  [51:48];
    green = temp_green [51:48];
  end
  10'd13: begin
    red   = temp_red   [55:52];
    blue  = temp_blue  [55:52];
    green = temp_green [55:52];
  end
  10'd14: begin
    red   = temp_red   [59:56];
    blue  = temp_blue  [59:56];
    green = temp_green [59:56];
  end
  10'd15: begin
    red   = temp_red   [63:60];
    blue  = temp_blue  [63:60];
    green = temp_green [63:60];
  end
  10'd16: begin
    red   = temp_red   [67:64];
    blue  = temp_blue  [67:64];
    green = temp_green [67:64];
  end
  10'd17: begin
    red   = temp_red   [71:68];
    blue  = temp_blue  [71:68];
    green = temp_green [71:68];
  end
  10'd18: begin
    red   = temp_red   [75:72];
    blue  = temp_blue  [75:72];
    green = temp_green [75:72];
  end
  10'd19: begin
    red   = temp_red   [79:76];
    blue  = temp_blue  [79:76];
    green = temp_green [79:76];
  end
  10'd20: begin
    red   = temp_red   [83:80];
    blue  = temp_blue  [83:80];
    green = temp_green [83:80];
  end
  10'd21: begin
    red   = temp_red   [87:84];
    blue  = temp_blue  [87:84];
    green = temp_green [87:84];
  end
  10'd22: begin
    red   = temp_red   [91:88];
    blue  = temp_blue  [91:88];
    green = temp_green [91:88];
  end
  10'd23: begin
    red   = temp_red   [95:92];
    blue  = temp_blue  [95:92];
    green = temp_green [95:92];
  end
  10'd24: begin
    red   = temp_red   [99:96];
    blue  = temp_blue  [99:96];
    green = temp_green [99:96];
  end
  10'd25: begin
    red   = temp_red   [103:100];
    blue  = temp_blue  [103:100];
    green = temp_green [103:100];
  end
  10'd26: begin
    red   = temp_red   [107:104];
    blue  = temp_blue  [107:104];
    green = temp_green [107:104];
  end
  10'd27: begin
    red   = temp_red   [111:108];
    blue  = temp_blue  [111:108];
    green = temp_green [111:108];
  end
  10'd28: begin
    red   = temp_red   [115:112];
    blue  = temp_blue  [115:112];
    green = temp_green [115:112];
  end
  10'd29: begin
    red   = temp_red   [119:116];
    blue  = temp_blue  [119:116];
    green = temp_green [119:116];
  end
  10'd30: begin
    red   = temp_red   [123:120];
    blue  = temp_blue  [123:120];
    green = temp_green [123:120];
  end
  10'd31: begin
    red   = temp_red   [127:124];
    blue  = temp_blue  [127:124];
    green = temp_green [127:124];
  end
  10'd32: begin
    red   = temp_red   [131:128];
    blue  = temp_blue  [131:128];
    green = temp_green [131:128];
  end
  10'd33: begin
    red   = temp_red   [135:132];
    blue  = temp_blue  [135:132];
    green = temp_green [135:132];
  end
  10'd34: begin
    red   = temp_red   [139:136];
    blue  = temp_blue  [139:136];
    green = temp_green [139:136];
  end
  10'd35: begin
    red   = temp_red   [143:140];
    blue  = temp_blue  [143:140];
    green = temp_green [143:140];
  end
  10'd36: begin
    red   = temp_red   [147:144];
    blue  = temp_blue  [147:144];
    green = temp_green [147:144];
  end
  10'd37: begin
    red   = temp_red   [151:148];
    blue  = temp_blue  [151:148];
    green = temp_green [151:148];
  end
  10'd38: begin
    red   = temp_red   [155:152];
    blue  = temp_blue  [155:152];
    green = temp_green [155:152];
  end
  10'd39: begin
    red   = temp_red   [159:156];
    blue  = temp_blue  [159:156];
    green = temp_green [159:156];
  end
  10'd40: begin
    red   = temp_red   [163:160];
    blue  = temp_blue  [163:160];
    green = temp_green [163:160];
  end
  10'd41: begin
    red   = temp_red   [167:164];
    blue  = temp_blue  [167:164];
    green = temp_green [167:164];
  end
  10'd42: begin
    red   = temp_red   [171:168];
    blue  = temp_blue  [171:168];
    green = temp_green [171:168];
  end
  10'd43: begin
    red   = temp_red   [175:172];
    blue  = temp_blue  [175:172];
    green = temp_green [175:172];
  end
  10'd44: begin
    red   = temp_red   [179:176];
    blue  = temp_blue  [179:176];
    green = temp_green [179:176];
  end
  10'd45: begin
    red   = temp_red   [183:180];
    blue  = temp_blue  [183:180];
    green = temp_green [183:180];
  end
  10'd46: begin
    red   = temp_red   [187:184];
    blue  = temp_blue  [187:184];
    green = temp_green [187:184];
  end
  10'd47: begin
    red   = temp_red   [191:188];
    blue  = temp_blue  [191:188];
    green = temp_green [191:188];
  end
  10'd48: begin
    red   = temp_red   [195:192];
    blue  = temp_blue  [195:192];
    green = temp_green [195:192];
  end
  10'd49: begin
    red   = temp_red   [199:196];
    blue  = temp_blue  [199:196];
    green = temp_green [199:196];
  end
  10'd50: begin
    red   = temp_red   [203:200];
    blue  = temp_blue  [203:200];
    green = temp_green [203:200];
  end
  10'd51: begin
    red   = temp_red   [207:204];
    blue  = temp_blue  [207:204];
    green = temp_green [207:204];
  end
  10'd52: begin
    red   = temp_red   [211:208];
    blue  = temp_blue  [211:208];
    green = temp_green [211:208];
  end
  10'd53: begin
    red   = temp_red   [215:212];
    blue  = temp_blue  [215:212];
    green = temp_green [215:212];
  end
  10'd54: begin
    red   = temp_red   [219:216];
    blue  = temp_blue  [219:216];
    green = temp_green [219:216];
  end
  10'd55: begin
    red   = temp_red   [223:220];
    blue  = temp_blue  [223:220];
    green = temp_green [223:220];
  end
  10'd56: begin
    red   = temp_red   [227:224];
    blue  = temp_blue  [227:224];
    green = temp_green [227:224];
  end
  10'd57: begin
    red   = temp_red   [231:228];
    blue  = temp_blue  [231:228];
    green = temp_green [231:228];
  end
  10'd58: begin
    red   = temp_red   [235:232];
    blue  = temp_blue  [235:232];
    green = temp_green [235:232];
  end
  10'd59: begin
    red   = temp_red   [239:236];
    blue  = temp_blue  [239:236];
    green = temp_green [239:236];
  end
  10'd60: begin
    red   = temp_red   [243:240];
    blue  = temp_blue  [243:240];
    green = temp_green [243:240];
  end
  10'd61: begin
    red   = temp_red   [247:244];
    blue  = temp_blue  [247:244];
    green = temp_green [247:244];
  end
  10'd62: begin
    red   = temp_red   [251:248];
    blue  = temp_blue  [251:248];
    green = temp_green [251:248];
  end
  10'd63: begin
    red   = temp_red   [255:252];
    blue  = temp_blue  [255:252];
    green = temp_green [255:252];
  end
  default: begin
    red   = '0;
    blue  = '0;
    green = '0;
  end
  endcase
end


endmodule