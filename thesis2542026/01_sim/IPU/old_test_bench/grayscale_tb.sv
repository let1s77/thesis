`timescale 1ns/10ps
`define INTERVAL 10.0

module grayscale_tb;
    
    bit clk;
    always #(`INTERVAL/2) clk = ~clk;

    grayscale_if vif(clk);

    grayscale dut (
        .i_clk    (vif.clk),
        .i_rst_n  (vif.rst_n),
        .i_color  (vif.color),
        .i_mode   (vif.mode),
        .o_gray   (vif.gray)
    );

    reg [23:0] pattern [0:9];
    reg [7:0]  golden  [0:29];
    integer i, err;

    initial begin
        $readmemh("pattern.hex", pattern);
        $readmemh("golden.hex", golden);
        
        err = 0;
        vif.rst_n = 0;
        vif.cb.color <= 0;
        vif.cb.mode  <= 0;

        #(`INTERVAL * 2);
        vif.rst_n = 1;
        @(vif.cb); // Wait one cycle after reset
        
        for(i = 0; i < 10; i = i + 1) begin
            $display("------------- Pattern %d: %h -------------", i+1, pattern[i]);
            
            // Apply new input and mode 0
            @(vif.cb);
            vif.cb.color <= pattern[i];
            vif.cb.mode  <= 2'b00;
            
            // Wait for DUT to process (1 cycle latency)
            @(vif.cb);
            @(vif.cb); // Extra cycle to ensure output is stable
            check_result(golden[3*i], "Round-up");

            // Change to mode 1 (color unchanged)
            @(vif.cb);
            vif.cb.mode <= 2'b01;
            
            // Wait for DUT to process
            @(vif.cb);
            @(vif.cb); // Extra cycle to ensure output is stable
            check_result(golden[3*i+1], "Round-down");

            // Change to mode 2 (color unchanged)
            @(vif.cb);
            vif.cb.mode <= 2'b10;
            
            // Wait for DUT to process
            @(vif.cb);
            @(vif.cb); // Extra cycle to ensure output is stable
            check_result(golden[3*i+2], "Round-to-even");
        end
        
        // Phần báo cáo kết quả giữ nguyên như cũ
        if(err === 0) $display("SIMULATION PASS !!");
        else $display("SIMULATION FAILED with %d errors", err);
        $finish;
    end

    // Cập nhật Task check_result để đọc trực tiếp từ clocking block
    task check_result(input [7:0] exp, input string name);
        if(vif.cb.gray === exp)
            $display("%s is correct.", name);
        else begin
            $display("%s is wrong. Your result is %d, but %d is expected.", name, vif.cb.gray, exp);
            err = err + 1;
        end
    endtask

endmodule