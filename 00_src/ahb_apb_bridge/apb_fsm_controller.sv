//==============================================================================
// Module: APB_FSM_Controller
// Description: APB FSM Controller for AHB-APB Bridge
//              - State machine to control APB transactions
//              - Generates APB control signals (Pwrite, Penable, Pselx)
//              - Handles both read and write operations with pipelining
//==============================================================================

module APB_FSM_Controller (
    // Clock and Reset
    input  logic        Hclk,
    input  logic        Hresetn,
    
    // Control Inputs
    input  logic        valid,
    input  logic        Hwrite,
    input  logic        Hwritereg,
    
    // Address Inputs (Pipeline)
    input  logic [31:0] Haddr,
    input  logic [31:0] Haddr1,
    input  logic [31:0] Haddr2,
    
    // Data Inputs (Pipeline)
    input  logic [31:0] Hwdata,
    input  logic [31:0] Hwdata1,
    input  logic [31:0] Hwdata2,
    input  logic [31:0] Prdata,
    
    // Peripheral Select Input
    input  logic [2:0]  tempselx,
    
    // APB Outputs
    output logic        Pwrite,
    output logic        Penable,
    output logic [2:0]  Pselx,
    output logic [31:0] Paddr,
    output logic [31:0] Pwdata,
    
    // AHB Ready Output
    output logic        Hreadyout
);

    //==========================================================================
    // State Encoding
    //==========================================================================
    typedef enum logic [2:0] {
        ST_IDLE     = 3'b000,
        ST_WWAIT    = 3'b001,
        ST_READ     = 3'b010,
        ST_WRITE    = 3'b011,
        ST_WRITEP   = 3'b100,
        ST_RENABLE  = 3'b101,
        ST_WENABLE  = 3'b110,
        ST_WENABLEP = 3'b111
    } state_t;

    //==========================================================================
    // State Registers
    //==========================================================================
    state_t PRESENT_STATE, NEXT_STATE;

    //==========================================================================
    // Temporary Output Registers (Combinational)
    //==========================================================================
    logic        Penable_temp;
    logic        Hreadyout_temp;
    logic        Pwrite_temp;
    logic [2:0]  Pselx_temp;
    logic [31:0] Paddr_temp;
    logic [31:0] Pwdata_temp;

    //==========================================================================
    // Present State Logic (Sequential)
    //==========================================================================
    always_ff @(posedge Hclk or negedge Hresetn) begin : PRESENT_STATE_LOGIC
        if (~Hresetn)
            PRESENT_STATE <= ST_IDLE;
        else
            PRESENT_STATE <= NEXT_STATE;
    end

    //==========================================================================
    // Next State Logic (Combinational)
    //==========================================================================
    always_comb begin : NEXT_STATE_LOGIC
        case (PRESENT_STATE)
            
            ST_IDLE: begin
                if (~valid)
                    NEXT_STATE = ST_IDLE;
                else if (valid && Hwrite)
                    NEXT_STATE = ST_WWAIT;
                else 
                    NEXT_STATE = ST_READ;
            end

            ST_WWAIT: begin
                if (~valid)
                    NEXT_STATE = ST_WRITE;
                else
                    NEXT_STATE = ST_WRITEP;
            end

            ST_READ: begin
                NEXT_STATE = ST_RENABLE;
            end

            ST_WRITE: begin
                if (~valid)
                    NEXT_STATE = ST_WENABLE;
                else
                    NEXT_STATE = ST_WENABLEP;
            end

            ST_WRITEP: begin
                NEXT_STATE = ST_WENABLEP;
            end

            ST_RENABLE: begin
                if (~valid)
                    NEXT_STATE = ST_IDLE;
                else if (valid && Hwrite)
                    NEXT_STATE = ST_WWAIT;
                else
                    NEXT_STATE = ST_READ;
            end

            ST_WENABLE: begin
                if (~valid)
                    NEXT_STATE = ST_IDLE;
                else if (valid && Hwrite)
                    NEXT_STATE = ST_WWAIT;
                else
                    NEXT_STATE = ST_READ;
            end

            ST_WENABLEP: begin
                if (~valid && Hwritereg)
                    NEXT_STATE = ST_WRITE;
                else if (valid && Hwritereg)
                    NEXT_STATE = ST_WRITEP;
                else
                    NEXT_STATE = ST_READ;
            end

            default: begin
                NEXT_STATE = ST_IDLE;
            end
        endcase
    end

    //==========================================================================
    // Output Logic (Combinational)
    //==========================================================================
    always_comb begin : OUTPUT_COMBINATIONAL_LOGIC
        // Default values
        Paddr_temp     = Paddr;
        Pwrite_temp    = Pwrite;
        Pselx_temp     = Pselx;
        Penable_temp   = Penable;
        Pwdata_temp    = Pwdata;
        Hreadyout_temp = Hreadyout;

        case (PRESENT_STATE)
            
            ST_IDLE: begin
                if (valid && ~Hwrite) begin : IDLE_TO_READ
                    Paddr_temp     = Haddr;
                    Pwrite_temp    = Hwrite;
                    Pselx_temp     = tempselx;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
                else if (valid && Hwrite) begin : IDLE_TO_WWAIT
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b1;
                end
                else begin : IDLE_TO_IDLE
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b1;
                end
            end

            ST_WWAIT: begin
                if (~valid) begin : WAIT_TO_WRITE
                    Paddr_temp     = Haddr1;
                    Pwrite_temp    = 1'b1;
                    Pselx_temp     = tempselx;
                    Penable_temp   = 1'b0;
                    Pwdata_temp    = Hwdata;
                    Hreadyout_temp = 1'b0;
                end
                else begin : WAIT_TO_WRITEP
                    Paddr_temp     = Haddr1;
                    Pwrite_temp    = 1'b1;
                    Pselx_temp     = tempselx;
                    Pwdata_temp    = Hwdata;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
            end

            ST_READ: begin : READ_TO_RENABLE
                Penable_temp   = 1'b1;
                Hreadyout_temp = 1'b1;
            end

            ST_WRITE: begin
                if (~valid) begin : WRITE_TO_WENABLE
                    Penable_temp   = 1'b1;
                    Hreadyout_temp = 1'b1;
                end
                else begin : WRITE_TO_WENABLEP
                    Penable_temp   = 1'b1;
                    Hreadyout_temp = 1'b1;
                end
            end

            ST_WRITEP: begin : WRITEP_TO_WENABLEP
                Penable_temp   = 1'b1;
                Hreadyout_temp = 1'b1;
            end

            ST_RENABLE: begin
                if (valid && ~Hwrite) begin : RENABLE_TO_READ
                    Paddr_temp     = Haddr;
                    Pwrite_temp    = Hwrite;
                    Pselx_temp     = tempselx;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
                else if (valid && Hwrite) begin : RENABLE_TO_WWAIT
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b1;
                end
                else begin : RENABLE_TO_IDLE
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b1;
                end
            end

            ST_WENABLEP: begin
                if (~valid && Hwritereg) begin : WENABLEP_TO_WRITEP
                    Paddr_temp     = Haddr2;
                    Pwrite_temp    = Hwrite;
                    Pselx_temp     = tempselx;
                    Penable_temp   = 1'b0;
                    Pwdata_temp    = Hwdata;
                    Hreadyout_temp = 1'b0;
                end
                else begin : WENABLEP_TO_WRITE_OR_READ
                    Paddr_temp     = Haddr2;
                    Pwrite_temp    = Hwrite;
                    Pselx_temp     = tempselx;
                    Pwdata_temp    = Hwdata;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
            end

            ST_WENABLE: begin
                if (~valid && Hwritereg) begin : WENABLE_TO_IDLE
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
                else begin : WENABLE_TO_WAIT_OR_READ
                    Pselx_temp     = 3'b000;
                    Penable_temp   = 1'b0;
                    Hreadyout_temp = 1'b0;
                end
            end

            default: begin
                Pselx_temp     = 3'b000;
                Penable_temp   = 1'b0;
                Hreadyout_temp = 1'b1;
            end
        endcase
    end

    //==========================================================================
    // Output Logic (Sequential)
    //==========================================================================
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (~Hresetn) begin
            Paddr     <= 32'h0;
            Pwrite    <= 1'b0;
            Pselx     <= 3'b000;
            Pwdata    <= 32'h0;
            Penable   <= 1'b0;
            Hreadyout <= 1'b0;
        end
        else begin
            Paddr     <= Paddr_temp;
            Pwrite    <= Pwrite_temp;
            Pselx     <= Pselx_temp;
            Pwdata    <= Pwdata_temp;
            Penable   <= Penable_temp;
            Hreadyout <= Hreadyout_temp;
        end
    end

endmodule
