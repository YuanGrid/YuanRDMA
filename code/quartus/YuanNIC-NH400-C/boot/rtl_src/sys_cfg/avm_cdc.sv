`default_nettype none
`timescale 1ns/1ps
module avm_cdc#(
    parameter       ADDR_W              = 28,
    parameter       DATA_W              = 32
)(
    input   wire    [ADDR_W-1:0]        s_avm_addr ,
    input   wire    [7:0]               s_avm_byte ,
    input   wire                        s_avm_read ,
    input   wire                        s_avm_write,
    input   wire    [2*DATA_W-1:0]      s_avm_wdat ,
    input   wire    [3:0]               s_avm_bcnt ,
    output  reg                         s_avm_wait ,
    output  reg     [2*DATA_W-1:0]      s_avm_rdat ,
    output  reg                         s_avm_rvld ,
    output  reg     [1:0]               s_avm_rspo ,
    output  reg                         s_avm_wrsp ,
    output  reg     [ADDR_W:0]          m_avm_addr ,
    output  reg                         m_avm_read ,
    output  reg                         m_avm_write,
    output  reg     [DATA_W-1:0]        m_avm_wdat ,
    input   wire                        m_avm_wait ,
    input   wire    [DATA_W-1:0]        m_avm_rdat ,
    input   wire                        m_avm_rvld ,
    input   wire    [1:0]               m_avm_rspo ,
    input   wire                        m_avm_wrsp ,
    input   wire                        s_clk,
    input   wire                        m_clk,
    input   wire                        rst_n
);
    localparam S_IDLE           = 2'b00;
    localparam S_WAIT           = 2'b01;
    localparam S_END            = 2'b10;
    localparam M_IDLE           = 2'b00;
    localparam M_WAIT           = 2'b01;
    localparam M_END            = 2'b10;

    reg     [1:0]                       s_cur_sta;
    reg     [1:0]                       s_nxt_sta;
    reg     [1:0]                       m_cur_sta;
    reg     [1:0]                       m_nxt_sta;
    reg     [2:0]                       s_req_flag;
    reg     [2:0]                       m_resp_flag;
    reg     [ADDR_W-1:0]                s_avm_addr_reg ;
    reg                                 s_avm_read_reg ;
    reg                                 s_avm_write_reg;
    reg     [DATA_W-1:0]                s_avm_wdat_reg ;
    reg     [DATA_W-1:0]                m_avm_rdat_reg ;
    reg                                 m_avm_rvld_reg ;
    reg     [1:0]                       m_avm_rspo_reg ;
    reg                                 m_avm_wrsp_reg ;

    always @(posedge s_clk ) begin
        if(!rst_n)
            s_cur_sta <= S_IDLE;
        else  
            s_cur_sta <= s_nxt_sta;
    end

    always @(*) begin
        case (s_cur_sta)
            S_IDLE:
                if(s_avm_read | s_avm_write) 
                    s_nxt_sta = S_WAIT;
                else  
                    s_nxt_sta = S_IDLE;     
            S_WAIT:
                if(m_resp_flag[2])
                    s_nxt_sta = S_END; 
                else 
                    s_nxt_sta = S_WAIT;
            S_END:
                if(~m_resp_flag[2])
                    s_nxt_sta = S_IDLE;
                else 
                    s_nxt_sta = S_END;
            default: s_nxt_sta = S_IDLE;
        endcase
    end

    always @(posedge s_clk ) begin
        if(!rst_n)
            s_req_flag[0] <= 1'b0;
        else if(s_cur_sta == S_WAIT & m_resp_flag[2])
            s_req_flag[0] <= 1'b0;
        else if((!s_avm_wait) & (s_avm_read | s_avm_write))
            s_req_flag[0] <= 1'b1;
    end

    always @(posedge s_clk ) begin
        m_resp_flag[2:1] <= m_resp_flag[1:0];
    end
    
    always @(posedge s_clk ) begin
        if((s_avm_read | s_avm_write) & (!s_avm_wait))begin 
            s_avm_addr_reg  <= s_avm_addr;
            case (s_avm_byte)
                8'b00001111: s_avm_addr_reg[2:0] <= 3'd0;
                8'b00011110: s_avm_addr_reg[2:0] <= 3'd1;
                8'b00111100: s_avm_addr_reg[2:0] <= 3'd2;
                8'b01111000: s_avm_addr_reg[2:0] <= 3'd3;
                8'b11110000: s_avm_addr_reg[2:0] <= 3'd4;
                8'b11100000: s_avm_addr_reg[2:0] <= 3'd5;
                8'b11000000: s_avm_addr_reg[2:0] <= 3'd6;
                8'b10000000: s_avm_addr_reg[2:0] <= 3'd7;
                default: s_avm_addr_reg[2:0] <= 3'd0;
            endcase
            s_avm_read_reg  <= s_avm_read;
            s_avm_write_reg <= s_avm_write;
            s_avm_wdat_reg  <= s_avm_byte == 8'h0f ? s_avm_wdat[31:0]:s_avm_wdat[63:32];
        end  
    end

    always @(posedge s_clk ) begin
        if((!s_avm_wait) & (s_avm_read | s_avm_write))
            s_avm_wait <= 1'b1;
        else if(s_cur_sta == S_IDLE)
            s_avm_wait <= 1'b0;
    end

    always @(posedge s_clk ) begin
        if(s_cur_sta == S_WAIT)begin 
            s_avm_rdat <= {m_avm_rdat_reg,m_avm_rdat_reg};
            s_avm_rspo <= m_avm_rspo_reg;
        end 
    end

    always @(posedge s_clk ) begin
        if(s_cur_sta == S_WAIT & (m_resp_flag[2]))
            s_avm_rvld <= m_avm_rvld_reg;
        else 
            s_avm_rvld <= 1'b0;
    end

    always @(posedge s_clk ) begin
        if(s_cur_sta == S_WAIT & (m_resp_flag[2]))
            s_avm_wrsp <= m_avm_wrsp_reg;
        else 
            s_avm_wrsp <= 1'b0;
    end

    always @(posedge m_clk) begin
        if(!rst_n)
            m_cur_sta <= M_IDLE;
        else  
            m_cur_sta <= m_nxt_sta;
    end

    always @(*) begin
        case (m_cur_sta)
            M_IDLE:
                if(s_req_flag[2])
                    m_nxt_sta = S_WAIT;
                else 
                    m_nxt_sta = M_IDLE;

            S_WAIT:
                if(m_avm_rvld | m_avm_wrsp)
                    m_nxt_sta = M_END;
                else 
                    m_nxt_sta = S_WAIT;
            M_END:
                if(~s_req_flag[2])
                    m_nxt_sta = M_IDLE;
                else 
                    m_nxt_sta = M_END;
            default: m_nxt_sta = M_IDLE;
        endcase
    end

    always @(posedge m_clk ) begin
        s_req_flag[2:1] <= s_req_flag[1:0];
    end

    always @(posedge m_clk ) begin
        if(m_cur_sta == M_IDLE)
            m_resp_flag[0] <= 1'b0;
        else if(m_nxt_sta == M_END)
            m_resp_flag[0] <= 1'b1;
    end

    always @(posedge m_clk ) begin
        if(m_cur_sta == M_IDLE)begin 
            m_avm_addr  <= s_avm_addr_reg ;
            m_avm_wdat  <= s_avm_wdat_reg ;
        end  
    end

    always @(posedge m_clk ) begin
        if((!m_avm_wait) & m_avm_read)
            m_avm_read <= 1'b0;
        else if(m_cur_sta == M_IDLE & s_req_flag[2] & s_avm_read_reg)
            m_avm_read <= 1'b1;
        else if(m_cur_sta == M_IDLE)
            m_avm_read <= 1'b0;
    end

    always @(posedge m_clk ) begin
        if((!m_avm_wait) & m_avm_write)
            m_avm_write <= 1'b0;
        else if(m_cur_sta == M_IDLE & s_req_flag[2] & s_avm_write_reg)
            m_avm_write <= 1'b1;
        else if(m_cur_sta == M_IDLE)
            m_avm_write <= 1'b0;  
    end

    always @(posedge m_clk ) begin
        if(m_avm_rvld)begin 
            m_avm_rdat_reg <= m_avm_rdat;
            m_avm_rspo_reg <= m_avm_rspo;
        end  

        if(m_cur_sta == M_IDLE)begin 
            m_avm_rvld_reg <= 1'b0;
            m_avm_wrsp_reg <= 1'b0;
        end else if(m_avm_wrsp)begin 
            m_avm_rvld_reg <= 1'b0;
            m_avm_wrsp_reg <= 1'b1;
        end else if(m_avm_rvld)begin 
            m_avm_rvld_reg <= 1'b1;
            m_avm_wrsp_reg <= 1'b0;
        end 
    end

endmodule
