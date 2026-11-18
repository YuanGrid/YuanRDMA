`resetall
`default_nettype none
`timescale 1ns / 1ps

module axis_select #(
    parameter S_DATA_WIDTH                          = 1024,
    parameter S_EMTY_WIDTH                          = (S_DATA_WIDTH/64)*3,
    parameter S_INFRAME_WIDTH                       = (S_DATA_WIDTH/64),
    parameter S_USEF_WIDTH                          = $clog2(S_DATA_WIDTH/8),
    parameter AXIS_NUM                              = 2
)(          
    input   wire                                    clk,
    input   wire                                    rst_n,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tvalid,
    input   wire    [AXIS_NUM*S_DATA_WIDTH-1:0]     s_axis_tdata,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tlast,
    input   wire    [AXIS_NUM*37-1:0]               s_axis_info,
    input   wire    [AXIS_NUM*S_USEF_WIDTH-1:0]     s_axis_usef,
    output  reg     [AXIS_NUM-1:0]                  s_axis_tready,

    output  reg                                     m_axis_tvalid,
    output  reg                                     m_axis_qdma,
    output  reg     [S_DATA_WIDTH-1:0]              m_axis_tdata,
    output  reg                                     m_axis_tlast,
    output  reg     [$clog2(S_DATA_WIDTH/8)-1:0]    m_axis_usef,
    output  reg     [36:0]                          m_axis_info,
    input   wire                                    m_axis_tready
);
    reg     [AXIS_NUM-1:0]                          select;
    reg     [AXIS_NUM-1:0]                          axis_vld;
    reg     [AXIS_NUM-1:0]                          axis_last;
    reg     [AXIS_NUM-1:0]                          axis_last_reg;
    reg                                             s_axis_reg_vld;
    reg     [S_DATA_WIDTH-1:0]                      s_axis_data_reg;
    reg     [$clog2(S_DATA_WIDTH/8)-1:0]            s_axis_usef_reg;
    reg     [37-1:0]                                s_axis_info_reg;
    reg                                             s_axis_last_reg;
    reg                                             m_axis_tready_d;

    generate
        for (genvar i=0 ; i<AXIS_NUM ; i=i+1) begin
            assign axis_vld[i]  = s_axis_tvalid[i] & s_axis_tready[i];
            assign axis_last[i] = s_axis_tvalid[i] & s_axis_tready[i] & s_axis_tlast[i];
            assign s_axis_tready[i] = select[i] & m_axis_tready;

            always @(posedge clk ) begin
                if(!rst_n)
                    axis_last_reg[i] <= 1'b0;
                else if(axis_last[i])
                    axis_last_reg[i] <= 1'b1;
                else if(|axis_vld)
                    axis_last_reg[i] <= 1'b0;
            end
        end
    endgenerate

    always @(posedge clk ) begin
        if(!rst_n)
            select <= 2'b0;
        else begin 
            case (select)
                2'b00:
                    if(s_axis_tvalid[0])
                        select <= 2'b01;
                    else if(s_axis_tvalid[1])
                        select <= 2'b10;
                    else 
                        select <= 2'b00;
                2'b01:
                    if(m_axis_tready & axis_last[0] & s_axis_tvalid[1])
                        select <= 2'b10;
                    else if(m_axis_tready & axis_last_reg[0] & s_axis_tvalid[1])
                        select <= 2'b10;
                    else 
                        select <= 2'b01;
                2'b10:
                    if(m_axis_tready & axis_last[1] & s_axis_tvalid[0])
                        select <= 2'b01;
                    else if(m_axis_tready & axis_last_reg[1] & s_axis_tvalid[0])
                        select <= 2'b01;
                    else 
                        select <= 2'b10;
                default: select <= 2'b00;
            endcase
        end 
    end

    always @(posedge clk ) begin
        if(axis_vld[0] & (~m_axis_tready) & m_axis_tready)begin 
            s_axis_data_reg <=s_axis_tdata[0*S_DATA_WIDTH+:S_DATA_WIDTH];
            s_axis_last_reg <=s_axis_tlast[0];
            s_axis_usef_reg <=s_axis_usef[0*S_USEF_WIDTH+:S_USEF_WIDTH];
            s_axis_info_reg <=s_axis_usef[0*37+:37];
        end else if(axis_vld[1] & (~m_axis_tready) & m_axis_tready)begin 
            s_axis_data_reg <=s_axis_tdata[1*S_DATA_WIDTH+:S_DATA_WIDTH];
            s_axis_last_reg <=s_axis_tlast[1];
            s_axis_usef_reg <=s_axis_usef[1*S_USEF_WIDTH+:S_USEF_WIDTH];
            s_axis_info_reg <=s_axis_usef[1*37+:37];
        end 
    end

    always @(posedge clk ) begin
        if(!rst_n)
            s_axis_reg_vld <= 1'b0;
        else if(m_axis_tready)
            s_axis_reg_vld <= 1'b0;
        else if((!axis_vld) & (~m_axis_tready) & m_axis_tready)
            s_axis_reg_vld <= 1'b1;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_qdma <= 1'b0;
        else if((axis_vld[0] | s_axis_reg_vld) & m_axis_tready)
            m_axis_qdma <= 1'b1;
        else if(m_axis_tvalid & m_axis_tlast & m_axis_tready)
            m_axis_qdma <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_tvalid <= 1'b0;
        else if(|axis_vld)
            m_axis_tvalid <= 1'b1;
        else if(m_axis_tvalid & m_axis_tlast & m_axis_tready)
            m_axis_tvalid <= 1'b0;
    end

    always @(posedge clk ) begin
        if(m_axis_tready & s_axis_reg_vld)begin 
            m_axis_tdata <= s_axis_data_reg;
            m_axis_tlast <= s_axis_last_reg;
            m_axis_usef  <= s_axis_usef_reg;
            m_axis_info  <= s_axis_info_reg;
        end else if(axis_vld[0] & m_axis_tready & (!s_axis_reg_vld))begin 
            m_axis_tdata <= s_axis_tdata[0*S_DATA_WIDTH+:S_DATA_WIDTH];
            m_axis_tlast <= s_axis_tlast[0];
            m_axis_usef  <= s_axis_usef[0*S_USEF_WIDTH+:S_USEF_WIDTH];
            m_axis_info  <= s_axis_info[0*37+:37];
        end else if(axis_vld[1] & m_axis_tready & (!s_axis_reg_vld))begin 
            m_axis_tdata <= s_axis_tdata[1*S_DATA_WIDTH+:S_DATA_WIDTH];
            m_axis_tlast <= s_axis_tlast[1];
            m_axis_usef  <= s_axis_usef[1*S_USEF_WIDTH+:S_USEF_WIDTH];
            m_axis_info  <= s_axis_info[1*37+:37];
        end 
    end
endmodule 
`resetall
