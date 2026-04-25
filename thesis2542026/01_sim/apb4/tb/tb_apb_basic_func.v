`timescale 1ns/1ps

module tb_apb_basic_func;

reg         PCLK;
reg         PRESETn;
reg         SWRITE;
reg  [31:0] SADDR;
reg  [31:0] SWDATA;
reg  [3:0]  SSTRB;
reg  [2:0]  SPROT;
reg         transfer;
wire [31:0] PRDATA;

integer test_count;
integer pass_count;
integer fail_count;
reg seen_setup;

APB_Wrapper dut (
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .SWRITE(SWRITE),
    .SADDR(SADDR),
    .SWDATA(SWDATA),
    .SSTRB(SSTRB),
    .SPROT(SPROT),
    .transfer(transfer),
    .PRDATA(PRDATA)
);

initial begin
    PCLK = 1'b0;
    forever #5 PCLK = ~PCLK;
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        seen_setup <= 1'b0;
    end else begin
        if (dut.Master.PSEL && !dut.Master.PENABLE) begin
            seen_setup <= 1'b1;
        end

        if (dut.Master.PENABLE && !dut.Master.PSEL) begin
            $display("[PROTO_ERR] PENABLE high while PSEL low at t=%0t", $time);
            fail_count = fail_count + 1;
        end

        if (dut.Master.PSEL && dut.Master.PENABLE && !seen_setup) begin
            $display("[PROTO_ERR] ACCESS without SETUP at t=%0t", $time);
            fail_count = fail_count + 1;
        end

        if (!dut.Master.PSEL) begin
            seen_setup <= 1'b0;
        end
    end
end

task do_reset;
begin
    PRESETn  = 1'b0;
    SWRITE   = 1'b0;
    SADDR    = 32'd0;
    SWDATA   = 32'd0;
    SSTRB    = 4'd0;
    SPROT    = 3'd0;
    transfer = 1'b0;
    repeat (3) @(posedge PCLK);
    PRESETn = 1'b1;
    repeat (1) @(posedge PCLK);
end
endtask

task apb_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
begin
    @(negedge PCLK);
    SWRITE   = 1'b1;
    SADDR    = addr;
    SWDATA   = data;
    SSTRB    = strb;
    transfer = 1'b1;

    // Wait through SETUP + ACCESS.
    repeat (2) @(posedge PCLK);

    @(negedge PCLK);
    transfer = 1'b0;
    SSTRB    = 4'd0;
    SWRITE   = 1'b0;

    // Force bus back to IDLE before starting next transaction.
    repeat (2) @(posedge PCLK);
end
endtask

task apb_read;
    input  [31:0] addr;
    input  [3:0]  strb;
    output [31:0] data;
    output        slverr;
begin
    @(negedge PCLK);
    SWRITE   = 1'b0;
    SADDR    = addr;
    SSTRB    = strb;
    transfer = 1'b1;

    // Wait through SETUP + ACCESS where PRDATA/PSLVERR are updated.
    repeat (2) @(posedge PCLK);
    #1;
    data   = PRDATA;
    slverr = dut.Slave.PSLVERR;

    @(negedge PCLK);
    transfer = 1'b0;
    SSTRB    = 4'd0;

    // Force bus back to IDLE before starting next transaction.
    repeat (2) @(posedge PCLK);
end
endtask

task check_equal32;
    input [639:0] test_name;
    input [31:0]  got;
    input [31:0]  exp;
begin
    test_count = test_count + 1;
    if (got !== exp) begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s: got=0x%08h exp=0x%08h", test_name, got, exp);
    end else begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s: value=0x%08h", test_name, got);
    end
end
endtask

task check_equal1;
    input [639:0] test_name;
    input         got;
    input         exp;
begin
    test_count = test_count + 1;
    if (got !== exp) begin
        fail_count = fail_count + 1;
        $display("[FAIL] %0s: got=%0b exp=%0b", test_name, got, exp);
    end else begin
        pass_count = pass_count + 1;
        $display("[PASS] %0s: value=%0b", test_name, got);
    end
end
endtask

task log_start;
    input [639:0] test_name;
begin
    $display("<at time %0t ns> [START] %0s", $time, test_name);
end
endtask

reg [31:0] rdata;
reg        rerr;

initial begin
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    rdata = 32'd0;
    rerr  = 1'b0;

    $display("\n===== APB Basic Functional Testbench Start =====");

    do_reset();

    log_start("Full-word write/read");
    apb_write(32'h00000010, 32'hA5A5_5A5A, 4'b1111);
    apb_read (32'h00000010, 4'b0000, rdata, rerr);
    check_equal32("Full-word write/read", rdata, 32'hA5A5_5A5A);
    check_equal1 ("Read with PSTRB=0 has no error", rerr, 1'b0);

    log_start("Partial write/read with PSTRB=0110");
    apb_write(32'h00000011, 32'hFF11_2277, 4'b0110);
    apb_read (32'h00000011, 4'b0000, rdata, rerr);
    check_equal32("Partial write 0110", rdata, 32'h0011_2200);
    check_equal1 ("Partial read no error", rerr, 1'b0);

    log_start("Partial write/read with PSTRB=1001");
    apb_write(32'h00000012, 32'h8899_AABB, 4'b1001);
    apb_read (32'h00000012, 4'b0000, rdata, rerr);
    check_equal32("Partial write 1001", rdata, 32'h8800_00BB);
    check_equal1 ("Partial read no error #2", rerr, 1'b0);

    log_start("Read with non-zero PSTRB expects PSLVERR");
    apb_read (32'h00000010, 4'b0001, rdata, rerr);
    check_equal1("Read with non-zero PSTRB -> PSLVERR", rerr, 1'b1);

    @(posedge PCLK);

    $display("===== APB Basic Functional Testbench Summary =====");
    $display("TOTAL=%0d PASS=%0d FAIL=%0d", test_count, pass_count, fail_count);

    if (fail_count == 0) begin
        $display("RESULT: PASS");
    end else begin
        $display("RESULT: FAIL");
    end

    $finish;
end

endmodule
