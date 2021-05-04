// © IBM Corp. 2020
// This softcore is licensed under and subject to the terms of the CC-BY 4.0
// license (https://creativecommons.org/licenses/by/4.0/legalcode). 
// Additional rights, including the right to physically implement a softcore 
// that is compliant with the required sections of the Power ISA 
// Specification, will be available at no cost via the OpenPOWER Foundation. 
// This README will be updated with additional information when OpenPOWER's 
// license is available.

`timescale 1 ns / 1 ns

//********************************************************************
//*
//* TITLE: Instruction Buffer
//*
//* NAME: iuq_ibuf.v
//*
//*********************************************************************

`include "tri_a2o.vh"

module iuq_ibuf(
   inout                              vdd,
   inout                              gnd,
   input [0:`NCLK_WIDTH-1]            nclk,
   input                              pc_iu_sg_2,
   input                              pc_iu_func_sl_thold_2,
   input                              clkoff_b,
   input                              act_dis,
   input                              tc_ac_ccflush_dc,
   input                              d_mode,
   input                              delay_lclkr,
   input                              mpw1_b,
   input                              mpw2_b,
   input                              scan_in,
   output                             scan_out,

   output                             ib_rm_rdy,
   input                              rm_ib_iu3_val,
   input [0:35]                       rm_ib_iu3_instr,

   input [0:3]                        uc_ib_iu3_invalid,
   input                              cp_iu_iu3_flush,
   input                              cp_flush_into_uc,
   input                              br_iu_redirect,
   input                              id_ib_iu4_stall,
   input			      uc_ib_iu3_flush_all,

   output [0:(`IBUFF_DEPTH/4)-1]       ib_ic_need_fetch,

   input [62-`EFF_IFAR_WIDTH:61]       bp_ib_iu3_ifar,
   input [0:3]                        bp_ib_iu3_val,
   input [0:`IBUFF_INSTR_WIDTH-1]      bp_ib_iu3_0_instr,
   input [0:`IBUFF_INSTR_WIDTH-1]      bp_ib_iu3_1_instr,
   input [0:`IBUFF_INSTR_WIDTH-1]      bp_ib_iu3_2_instr,
   input [0:`IBUFF_INSTR_WIDTH-1]      bp_ib_iu3_3_instr,
   input [62-`EFF_IFAR_WIDTH:61]       bp_ib_iu3_bta,

   output                             ib_uc_rdy,
   input [0:1]                        uc_ib_val,
   input                              uc_ib_done,
   input [0:31]                       uc_ib_instr0,
   input [0:31]                       uc_ib_instr1,
   input [62-`EFF_IFAR_WIDTH:61]       uc_ib_ifar0,
   input [62-`EFF_IFAR_WIDTH:61]       uc_ib_ifar1,
   input [0:3]                        uc_ib_ext0,
   input [0:3]                        uc_ib_ext1,

   output                             ib_id_iu4_0_valid,
   output [62-`EFF_IFAR_WIDTH:61]      ib_id_iu4_0_ifar,
   output [62-`EFF_IFAR_WIDTH:61]      ib_id_iu4_0_bta,
   output [0:`IBUFF_INSTR_WIDTH-1]     ib_id_iu4_0_instr,
   output [0:2]                       ib_id_iu4_0_ucode,
   output [0:3]                       ib_id_iu4_0_ucode_ext,
   output                             ib_id_iu4_0_isram,
   output                             ib_id_iu4_0_fuse_val,
   output [0:31]                      ib_id_iu4_0_fuse_data,

   output                             ib_id_iu4_1_valid,
   output [62-`EFF_IFAR_WIDTH:61]      ib_id_iu4_1_ifar,
   output [62-`EFF_IFAR_WIDTH:61]      ib_id_iu4_1_bta,
   output [0:`IBUFF_INSTR_WIDTH-1]     ib_id_iu4_1_instr,
   output [0:2]                       ib_id_iu4_1_ucode,
   output [0:3]                       ib_id_iu4_1_ucode_ext,
   output                             ib_id_iu4_1_isram,
   output                             ib_id_iu4_1_fuse_val,
   output [0:31]                      ib_id_iu4_1_fuse_data
   );

      // buffer constants
      parameter                          IDATA_WIDTH = (`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH + `EFF_IFAR_WIDTH); // 70 + 20 + 20
      parameter                          IBUFF_WIDTH = (`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH + `IBUFF_IFAR_WIDTH); // 70 + 20 + 20
      parameter                          IBUFF_DEPTH = (`IBUFF_DEPTH);

      // types for configurable width/depth

      wire                               cp_flush_d;
      wire                               cp_flush_q;
      wire                               br_iu_redirect_d;
      wire                               br_iu_redirect_q;

      // incoming valid
      wire [0:3]                         iu3_val;

      // incoming stall
      wire                               iu4_stall;

      // buffer latches
      reg [0:IBUFF_WIDTH-1]             buffer_data_din[0:`IBUFF_DEPTH-1];
      reg [0:IBUFF_WIDTH-1]             buffer_data_d[0:`IBUFF_DEPTH-1];
      reg [0:IBUFF_WIDTH-1]             buffer_data_q[0:`IBUFF_DEPTH-1];
      wire                               buffer_valid_act;
      wire [0:`IBUFF_DEPTH-1]             buffer_valid_din;
      wire [0:`IBUFF_DEPTH-1]             buffer_valid_d;
      wire [0:`IBUFF_DEPTH-1]             buffer_valid_q;
      wire                               buffer_head_act;
      wire [0:`IBUFF_DEPTH-1]             buffer_head_din;
      wire [0:`IBUFF_DEPTH-1]             buffer_head_d;
      wire [0:IBUFF_DEPTH-1]             buffer_head_q;
      wire                               buffer_tail_act;
      wire [0:`IBUFF_DEPTH-1]             buffer_tail_din;
      wire [0:`IBUFF_DEPTH-1]             buffer_tail_d;
      wire [0:IBUFF_DEPTH-1]             buffer_tail_q;
      reg  [0:`IBUFF_DEPTH*IBUFF_WIDTH-1] buffer_array_d;
      wire [0:`IBUFF_DEPTH*IBUFF_WIDTH-1] buffer_array_q;

      // stall buffer
      wire [0:IDATA_WIDTH-1]             stall_buffer_data0_d;
      wire [0:IDATA_WIDTH-1]             stall_buffer_data0_q;
      wire [0:IDATA_WIDTH-1]             stall_buffer_data1_d;
      wire [0:IDATA_WIDTH-1]             stall_buffer_data1_q;
      wire [0:1]                         stall_d;
      wire [0:1]                         stall_q;
      wire [0:1]                         stall_buffer_act;

      // buffer control
      wire                               buffer_valid_flush;
      wire [0:2]                         buffer_advance;
      wire [0:2]                         buffer_bypass;

      // ifar extension bits
      wire [60:61]                       ifar_1_ext;
      wire [60:61]                       ifar_2_ext;
      wire [60:61]                       ifar_3_ext;

      // data/valid in
      wire [0:3]                         valid_in;
      wire [0:IBUFF_WIDTH-1]             data0_in;
      wire [0:IBUFF_WIDTH-1]             data1_in;
      wire [0:IBUFF_WIDTH-1]             data2_in;
      wire [0:IBUFF_WIDTH-1]             data3_in;
      wire [0:IDATA_WIDTH-1]             fast_data0;
      wire [0:IDATA_WIDTH-1]             fast_data1;

      // data/valid out
      wire [0:1]                         valid_int;
      wire [0:1]                         valid_out;
      wire [0:IDATA_WIDTH-1]             data0_out;
      wire [0:IDATA_WIDTH-1]             data1_out;
      wire [0:IBUFF_WIDTH-1]             buffer0_ibuff_data;
      wire [0:IBUFF_WIDTH-1]             buffer1_ibuff_data;
      wire [0:IDATA_WIDTH-1]             buffer0_data;
      wire [0:IDATA_WIDTH-1]             buffer1_data;
      reg  [0:IBUFF_WIDTH-1]             buffer0_data_muxed[0:`IBUFF_DEPTH-1];
      reg  [0:IBUFF_WIDTH-1]             buffer1_data_muxed[0:`IBUFF_DEPTH-1];

      // output latches
      wire                               iu4_0_valid_din;
      reg                                iu4_0_valid_d;
      wire                               iu4_0_valid_q;
      wire [0:`IBUFF_INSTR_WIDTH-1]       iu4_0_instr_din;
      reg [0:`IBUFF_INSTR_WIDTH-1]        iu4_0_instr_d;
      wire [0:`IBUFF_INSTR_WIDTH-1]       iu4_0_instr_q;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_0_ifar_din;
      reg [62-`EFF_IFAR_WIDTH:61]         iu4_0_ifar_d;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_0_ifar_q;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_0_bta_din;
      reg [62-`EFF_IFAR_WIDTH:61]         iu4_0_bta_d;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_0_bta_q;
      wire [0:2]                         iu4_0_ucode_din;
      reg [0:2]                          iu4_0_ucode_d;
      wire [0:2]                         iu4_0_ucode_q;
      wire [0:3]                         iu4_0_ucode_ext_din;
      reg [0:3]                          iu4_0_ucode_ext_d;
      wire [0:3]                         iu4_0_ucode_ext_q;
      wire                               iu4_0_isram_din;
      reg                                iu4_0_isram_d;
      wire                               iu4_0_isram_q;
      wire                               iu4_0_fuse_val_din;
      reg                                iu4_0_fuse_val_d;
      wire                               iu4_0_fuse_val_q;
      wire [0:31]                        iu4_0_fuse_data_din;
      reg [0:31]                         iu4_0_fuse_data_d;
      wire [0:31]                        iu4_0_fuse_data_q;

      wire                               iu4_1_valid_din;
      reg                                iu4_1_valid_d;
      wire                               iu4_1_valid_q;
      wire [0:`IBUFF_INSTR_WIDTH-1]       iu4_1_instr_din;
      reg [0:`IBUFF_INSTR_WIDTH-1]        iu4_1_instr_d;
      wire [0:`IBUFF_INSTR_WIDTH-1]       iu4_1_instr_q;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_1_ifar_din;
      reg [62-`EFF_IFAR_WIDTH:61]         iu4_1_ifar_d;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_1_ifar_q;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_1_bta_din;
      reg [62-`EFF_IFAR_WIDTH:61]         iu4_1_bta_d;
      wire [62-`EFF_IFAR_WIDTH:61]        iu4_1_bta_q;
      wire [0:2]                         iu4_1_ucode_din;
      reg [0:2]                          iu4_1_ucode_d;
      wire [0:2]                         iu4_1_ucode_q;
      wire [0:3]                         iu4_1_ucode_ext_din;
      reg [0:3]                          iu4_1_ucode_ext_d;
      wire [0:3]                         iu4_1_ucode_ext_q;
      wire                               iu4_1_isram_din;
      reg                                iu4_1_isram_d;
      wire                               iu4_1_isram_q;
      wire                               iu4_1_fuse_val_din;
      reg                                iu4_1_fuse_val_d;
      wire                               iu4_1_fuse_val_q;
      wire [0:31]                        iu4_1_fuse_data_din;
      reg [0:31]                         iu4_1_fuse_data_d;
      wire [0:31]                        iu4_1_fuse_data_q;

      wire                               uc_select_d;
      wire                               uc_select_q;

      // ucode
      wire [0:1]                         iu4_uc_mode_din;
      reg [0:1]                          iu4_uc_mode_d;
      wire [0:1]                         iu4_uc_mode_q;

      wire [0:1]                         ucode_out;
      wire [0:1]                         uc_hole;
      wire                               uc_stall;
      wire                               uc_select;
      wire                               uc_swap;

      wire [0:1]                         cp_flush_into_uc_delay_d;
      wire [0:1]                         cp_flush_into_uc_delay_q;

      // error
      wire [0:1]                         error_hole;
      wire [0:2]                         error0_out;
      wire [0:2]                         error1_out;

      // fusion
      wire [0:1]                         fuse_en;

      // Pervasive
      wire                               pc_iu_func_sl_thold_1;
      wire                               pc_iu_func_sl_thold_0;
      wire                               pc_iu_func_sl_thold_0_b;
      wire                               pc_iu_sg_1;
      wire                               pc_iu_sg_0;
      wire                               force_t;

      // ties
      wire                               tiup;

      // scan chain
      parameter                          uc_select_offset = 0;
      parameter                          buffer_valid_offset = uc_select_offset + 1;
      parameter                          buffer_head_offset = buffer_valid_offset + `IBUFF_DEPTH;
      parameter                          buffer_tail_offset = buffer_head_offset + `IBUFF_DEPTH;
      parameter                          buffer_array_offset = buffer_tail_offset + `IBUFF_DEPTH;
      parameter                          stall_offset = buffer_array_offset + (`IBUFF_DEPTH*IBUFF_WIDTH-1+1);
      parameter                          stall_buffer_data0_offset = stall_offset + 2;
      parameter                          stall_buffer_data1_offset = stall_buffer_data0_offset + IDATA_WIDTH;
      parameter                          iu4_uc_mode_offset = stall_buffer_data1_offset + IDATA_WIDTH;
      parameter                          iu4_0_valid_offset = iu4_uc_mode_offset + 2;
      parameter                          iu4_0_instr_offset = iu4_0_valid_offset + 1;
      parameter                          iu4_0_ifar_offset = iu4_0_instr_offset + `IBUFF_INSTR_WIDTH;
      parameter                          iu4_0_bta_offset = iu4_0_ifar_offset + `EFF_IFAR_WIDTH;
      parameter                          iu4_0_ucode_offset = iu4_0_bta_offset + `EFF_IFAR_WIDTH;
      parameter                          iu4_0_ucode_ext_offset = iu4_0_ucode_offset + 3;
      parameter                          iu4_0_isram_offset = iu4_0_ucode_ext_offset + 4;
      parameter                          iu4_0_fuse_val_offset = iu4_0_isram_offset + 1;
      parameter                          iu4_0_fuse_data_offset = iu4_0_fuse_val_offset + 1;
      parameter                          iu4_1_valid_offset = iu4_0_fuse_data_offset + 32;
      parameter                          iu4_1_instr_offset = iu4_1_valid_offset + 1;
      parameter                          iu4_1_ifar_offset = iu4_1_instr_offset + `IBUFF_INSTR_WIDTH;
      parameter                          iu4_1_bta_offset = iu4_1_ifar_offset + `EFF_IFAR_WIDTH;
      parameter                          iu4_1_ucode_offset = iu4_1_bta_offset + `EFF_IFAR_WIDTH;
      parameter                          iu4_1_ucode_ext_offset = iu4_1_ucode_offset + 3;
      parameter                          iu4_1_isram_offset = iu4_1_ucode_ext_offset + 4;
      parameter                          iu4_1_fuse_val_offset = iu4_1_isram_offset + 1;
      parameter                          iu4_1_fuse_data_offset = iu4_1_fuse_val_offset + 1;
      parameter                          cp_flush_offset = iu4_1_fuse_data_offset + 32;
      parameter                          br_iu_redirect_offset = cp_flush_offset + 1;
      parameter                          cp_flush_into_uc_offset = br_iu_redirect_offset + 1;
      parameter                          scan_right = cp_flush_into_uc_offset + 2 - 1;

      // scan
      wire [0:scan_right]                siv;
      wire [0:scan_right]                sov;

      //---------------------------------------------------------------------
      // Logic
      //---------------------------------------------------------------------

      //tidn    <= '0';
      assign tiup = 1'b1;

      //cp_iu_i3_flush : tlb_miss, interrupt, exception(like div by 0), debug control
      //uc_ib_iu3_flush_all : microcode related flush.
      //br_iu_redirect_d : flush due to branch misprediction
      assign cp_flush_d = cp_iu_iu3_flush | uc_ib_iu3_flush_all;
      assign br_iu_redirect_d = br_iu_redirect & (~(cp_flush_q));
      assign cp_flush_into_uc_delay_d = {(cp_flush_into_uc), (cp_flush_into_uc_delay_q[0] & (~(cp_iu_iu3_flush)))};

      //--------------------------------------
      // incoming valid
      //--------------------------------------

      assign iu3_val = bp_ib_iu3_val & (~uc_ib_iu3_invalid);

      //--------------------------------------
      // ibuff control
      //--------------------------------------

      assign ifar_1_ext = (bp_ib_iu3_ifar[60:61] == 2'b10) ? 2'b11 :
                          (bp_ib_iu3_ifar[60:61] == 2'b01) ? 2'b10 :
                          2'b01;
      assign ifar_2_ext = {1'b1, bp_ib_iu3_ifar[61]};
      assign ifar_3_ext = 2'b11;

      assign buffer_valid_flush = cp_flush_q | br_iu_redirect_q;

      //buffer_advance
      //how many advance occur in buffer?
      //In other words, how many instruction is consumed by decoder?
      //In fact, there is stall buffer, for backpressure case.
      //so at least stall buffer can consume instruction buffer.
      //stall buffer occupancy can be checked by stall_q
      //if two stall buffer available --> buffer_advance2
      //if one stall buffer available --> buffer_advance1
      //  because stall_q[0] filled first, one stall buffer available only means 
      //  ~stall_q[1]
      //--> stall_q[1] means stall_q[0]
      //one hot encoding used.
      //buffer_advance[0] == 1'b1 --> no advance in buffer
      //buffer_advance[1] == 1'b1 --> 1 advance in buffer
      //buffer_advance[2] == 1'b1 --> 2 advance in buffer.
      //why 2 is maximum? 
      //  --> it is uarch design. fetch-decode-issue width is 2
      //
      /
      assign buffer_advance[0] = stall_q[1];
      assign buffer_advance[1] = stall_q[0] & (~stall_q[1]);
      assign buffer_advance[2] = (~stall_q[0]) & (~stall_q[1]);
        
      //--------------------------------------
      // ibuff
      //--------------------------------------

      //set latch inputs
	assign buffer_head_d = (buffer_valid_flush == 1'b1) ? {1'b1, {(`IBUFF_DEPTH-1){1'b0}}} :
                             buffer_head_din[0:`IBUFF_DEPTH - 1];
	assign buffer_tail_d = (buffer_valid_flush == 1'b1) ? {1'b1, {(`IBUFF_DEPTH-1){1'b0}}} :
                             buffer_tail_din[0:`IBUFF_DEPTH - 1];
      assign buffer_valid_d = ((~buffer_valid_flush) ? buffer_valid_din[0:`IBUFF_DEPTH - 1] : 0 );

      //construct buffer data
      assign data0_in[0:IBUFF_WIDTH - 1] = {bp_ib_iu3_0_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `IBUFF_IFAR_WIDTH:61]};
      assign data1_in[0:IBUFF_WIDTH - 1] = {bp_ib_iu3_1_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `IBUFF_IFAR_WIDTH:59], ifar_1_ext[60:61]};
      assign data2_in[0:IBUFF_WIDTH - 1] = {bp_ib_iu3_2_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `IBUFF_IFAR_WIDTH:59], ifar_2_ext[60:61]};
      assign data3_in[0:IBUFF_WIDTH - 1] = {bp_ib_iu3_3_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `IBUFF_IFAR_WIDTH:59], ifar_3_ext[60:61]};

      //construct fastpath/stall data
      assign fast_data0[0:IDATA_WIDTH - 1] = {bp_ib_iu3_0_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `EFF_IFAR_WIDTH:61]};
      assign fast_data1[0:IDATA_WIDTH - 1] = {bp_ib_iu3_1_instr[0:`IBUFF_INSTR_WIDTH - 1], bp_ib_iu3_bta, bp_ib_iu3_ifar[62 - `EFF_IFAR_WIDTH:59], ifar_1_ext[60:61]};
      
      // valid_in : if new incoming instruction has 
          // 4 valid input --> valid_in = 4'b1111,
          // 3 valid input --> valid_in = 4'b0111,
          // ...
          // 0 valid input --> valid_in = 4'b0000;
          // somewhat cumulative 1 passion
      assign valid_in[0:3] = iu3_val[0:3];

      assign buffer_valid_act = buffer_valid_flush | valid_in[0] | (buffer_valid_q[0] & (buffer_advance[1] | buffer_advance[2]));

      //buffer_valid_din / or buffer_valid_q
      //has valid flag for each instruction in buffer
      //they are not circular queue, they are growing 1s(ones) from 0th bit
      //if buffer advance, 0s expand from MSB(IBUFF_DETP-1'th bit)
      //if buffer is filled, 1s expend from LSB(0th bit)
      //ex) 3 instr valid --> IBUFF_DEPTH'b111000000000....
      assign buffer_valid_din[0:`IBUFF_DEPTH - 1] = (buffer_advance[0] == 1'b1 & valid_in[3] == 1'b1) ? {4'b1111, buffer_valid_q[0:`IBUFF_DEPTH - 5]} : // 4 in, zero out
                                                   (buffer_advance[1] == 1'b1 & valid_in[3] == 1'b1) ? {3'b111, buffer_valid_q[0:`IBUFF_DEPTH - 4]} :
                                                   (buffer_advance[2] == 1'b1 & valid_in[3] == 1'b1) ? {2'b11, buffer_valid_q[0:`IBUFF_DEPTH - 3]} :
                                                   (buffer_advance[0] == 1'b1 & valid_in[2] == 1'b1) ? {3'b111, buffer_valid_q[0:`IBUFF_DEPTH - 4]} :
                                                   (buffer_advance[1] == 1'b1 & valid_in[2] == 1'b1) ? {2'b11, buffer_valid_q[0:`IBUFF_DEPTH - 3]} :
                                                   (buffer_advance[2] == 1'b1 & valid_in[2] == 1'b1) ? {1'b1, buffer_valid_q[0:`IBUFF_DEPTH - 2]} :
                                                   (buffer_advance[0] == 1'b1 & valid_in[1] == 1'b1) ? {2'b11, buffer_valid_q[0:`IBUFF_DEPTH - 3]} :
                                                   (buffer_advance[1] == 1'b1 & valid_in[1] == 1'b1) ? {1'b1, buffer_valid_q[0:`IBUFF_DEPTH - 2]} :
                                                   (buffer_advance[2] == 1'b1 & valid_in[1] == 1'b1) ? buffer_valid_q[0:`IBUFF_DEPTH - 1] :
                                                   (buffer_advance[0] == 1'b1 & valid_in[0] == 1'b1) ? {1'b1, buffer_valid_q[0:`IBUFF_DEPTH - 2]} :
                                                   (buffer_advance[1] == 1'b1 & valid_in[0] == 1'b1) ? buffer_valid_q[0:`IBUFF_DEPTH - 1] :
                                                   (buffer_advance[2] == 1'b1 & valid_in[0] == 1'b1) ? {buffer_valid_q[1:`IBUFF_DEPTH - 1], 1'b0} :
                                                   (buffer_advance[0] == 1'b1 & valid_in[0] == 1'b0) ? buffer_valid_q[0:`IBUFF_DEPTH - 1] :
                                                   (buffer_advance[1] == 1'b1 & valid_in[0] == 1'b0) ? {buffer_valid_q[1:`IBUFF_DEPTH - 1], 1'b0} :
                                                   {buffer_valid_q[2:`IBUFF_DEPTH - 1], 2'b00}; // no in, 2 out
      // buffer bypass:
      // how many input instruction is consumed to processor backend, not from
      // buffer data.
      // if no valid instruction in buffer, they will use input
      // instruction(fast_data)
      // what if not enough instruction comes?
      //  ex) buffer_advance ==2, but no buffer valid.
      //      how do we know there are at least 2 valid fast_data?
      //      Because buffer_advance ==2 already means that there are 2 valid
      //      (fast_)data
      assign buffer_bypass[2] = (buffer_advance[2] == 1'b1 & buffer_valid_q[0] == 1'b0);
      assign buffer_bypass[1] = (buffer_advance[2] == 1'b1 & buffer_valid_q[0] == 1'b1 & buffer_valid_q[1] == 1'b0) | (buffer_advance[1] == 1'b1 & buffer_valid_q[0] == 1'b0);
      assign buffer_bypass[0] = (buffer_advance[2] == 1'b1 & buffer_valid_q[1] == 1'b1) | (buffer_advance[1] == 1'b1 & buffer_valid_q[0] == 1'b1) | (buffer_advance[0] == 1'b1);

      assign buffer_head_act = buffer_valid_flush | valid_in[0];
      
      // buffer head: 
      // indicate instruction buffer head.
      // only 1 bit is 1, other bits are 0.
      // it is maintained as circular queue fashion.
      // if new instruction fills in, head move to MSB
      // # of instruction fills in is calculated from 
      // number of valid input - bypassed input
      // initial value : MSB=1 (see buffer_head_d)
      assign buffer_head_din[0:`IBUFF_DEPTH - 1] = (buffer_bypass[2] == 1'b1 & valid_in[3] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 2:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 3]} :
                                                  (buffer_bypass[2] == 1'b1 & valid_in[2] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 2]} :
                                                  (buffer_bypass[1] == 1'b1 & valid_in[3] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 3:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 4]} :
                                                  (buffer_bypass[1] == 1'b1 & valid_in[2] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 2:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 3]} :
                                                  (buffer_bypass[1] == 1'b1 & valid_in[1] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 2]} :
                                                  (buffer_bypass[0] == 1'b1 & valid_in[3] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 4:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 5]} :
                                                  (buffer_bypass[0] == 1'b1 & valid_in[2] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 3:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 4]} :
                                                  (buffer_bypass[0] == 1'b1 & valid_in[1] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 2:`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 3]} :
                                                  (buffer_bypass[0] == 1'b1 & valid_in[0] == 1'b1) ? {buffer_head_q[`IBUFF_DEPTH - 1], buffer_head_q[0:`IBUFF_DEPTH - 2]} :
                                                  buffer_head_q[0:`IBUFF_DEPTH - 1];

      assign buffer_tail_act = buffer_valid_flush | (buffer_valid_q[0] & (buffer_advance[1] | buffer_advance[2]));


      // buffer tail:
      // indicate instruction buffer tail.
      // only 1 bit is 1, other bits are 0
      // initial value is MSB=1 (see buffer_tail_d!)
      // it is also for circular queue, which is same as buffer head.
      // buffer tail is advanced when buffer data is comsumed.
      // Note that buffer_advance != number of buffer data used.
      // buffer_advance is the number of instruction consumed.
      // buffer_advance includes "fast data" comsumption.
      // So for caculating tail, need to check buffer_valid flag
      assign buffer_tail_din[0:`IBUFF_DEPTH - 1] = (buffer_advance[2] == 1'b1 & buffer_valid_q[1] == 1'b1) ? {buffer_tail_q[`IBUFF_DEPTH - 2:`IBUFF_DEPTH - 1], buffer_tail_q[0:`IBUFF_DEPTH - 3]} :
                                                   (buffer_advance[2] == 1'b1 & buffer_valid_q[0] == 1'b1) ? {buffer_tail_q[`IBUFF_DEPTH - 1], buffer_tail_q[0:`IBUFF_DEPTH - 2]} :
                                                   (buffer_advance[1] == 1'b1 & buffer_valid_q[0] == 1'b1) ? {buffer_tail_q[`IBUFF_DEPTH - 1], buffer_tail_q[0:`IBUFF_DEPTH - 2]} :
                                                    buffer_tail_q[0:`IBUFF_DEPTH - 1];

      //configurable depth buffer
      //real instrution buffer's din
      //circular queue with 4 possible input
      //no need to erase tail --> just remove buffer_valid bit
      //just add new instruction to head.
      //0~3th din is separate from general case because of circular wrapping
      //just need to know ith case.
      //din is calculated from buffer bypass and buffer head.
      //ex) no bypass, head is itself --> data0_in
      //    no bypass, head is 2 previous index --> data2_in
      //    2 bypass, head is itself --> data2_in
      //what happen if not enough datax_in?
      //this case is treated by buffer valid signal. for buffer data, just put
      //in garbage value.
      generate
         begin : xhdl1
            genvar                             i;
            for (i = 0; i <= `IBUFF_DEPTH - 1; i = i + 1)
            begin : buffer_gen
       always @( * )
              begin
               if (i == 0)
               begin : b0

                   buffer_data_din[0] <= (buffer_bypass[0] == 1'b1 & buffer_head_q[0] == 1'b1) ? data0_in :
                                              (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data1_in :
                                              (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 2] == 1'b1) ? data2_in :
                                              (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 3] == 1'b1) ? data3_in :
                                              (buffer_bypass[1] == 1'b1 & buffer_head_q[0] == 1'b1) ? data1_in :
                                              (buffer_bypass[1] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data2_in :
                                              (buffer_bypass[1] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 2] == 1'b1) ? data3_in :
                                              (buffer_bypass[2] == 1'b1 & buffer_head_q[0] == 1'b1) ? data2_in :
                                              (buffer_bypass[2] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data3_in :
                                              buffer_data_q[0];
               end

            if (i == 1)
            begin : b1
                buffer_data_din[1] <= (buffer_bypass[0] == 1'b1 & buffer_head_q[1] == 1'b1) ? data0_in :
                                           (buffer_bypass[0] == 1'b1 & buffer_head_q[0] == 1'b1) ? data1_in :
                                           (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data2_in :
                                           (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 2] == 1'b1) ? data3_in :
                                           (buffer_bypass[1] == 1'b1 & buffer_head_q[1] == 1'b1) ? data1_in :
                                           (buffer_bypass[1] == 1'b1 & buffer_head_q[0] == 1'b1) ? data2_in :
                                           (buffer_bypass[1] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data3_in :
                                           (buffer_bypass[2] == 1'b1 & buffer_head_q[1] == 1'b1) ? data2_in :
                                           (buffer_bypass[2] == 1'b1 & buffer_head_q[0] == 1'b1) ? data3_in :
                                           buffer_data_q[1];
            end

         if (i == 2)
         begin : b2
             buffer_data_din[2] <= (buffer_bypass[0] == 1'b1 & buffer_head_q[2] == 1'b1) ? data0_in :
                                        (buffer_bypass[0] == 1'b1 & buffer_head_q[1] == 1'b1) ? data1_in :
                                        (buffer_bypass[0] == 1'b1 & buffer_head_q[0] == 1'b1) ? data2_in :
                                        (buffer_bypass[0] == 1'b1 & buffer_head_q[`IBUFF_DEPTH - 1] == 1'b1) ? data3_in :
                                        (buffer_bypass[1] == 1'b1 & buffer_head_q[2] == 1'b1) ? data1_in :
                                        (buffer_bypass[1] == 1'b1 & buffer_head_q[1] == 1'b1) ? data2_in :
                                        (buffer_bypass[1] == 1'b1 & buffer_head_q[0] == 1'b1) ? data3_in :
                                        (buffer_bypass[2] == 1'b1 & buffer_head_q[2] == 1'b1) ? data2_in :
                                        (buffer_bypass[2] == 1'b1 & buffer_head_q[1] == 1'b1) ? data3_in :
                                        buffer_data_q[2];
         end

      if (i == 3)
      begin : b3
          buffer_data_din[3] <= (buffer_bypass[0] == 1'b1 & buffer_head_q[3] == 1'b1) ? data0_in :
                                     (buffer_bypass[0] == 1'b1 & buffer_head_q[2] == 1'b1) ? data1_in :
                                     (buffer_bypass[0] == 1'b1 & buffer_head_q[1] == 1'b1) ? data2_in :
                                     (buffer_bypass[0] == 1'b1 & buffer_head_q[0] == 1'b1) ? data3_in :
                                     (buffer_bypass[1] == 1'b1 & buffer_head_q[3] == 1'b1) ? data1_in :
                                     (buffer_bypass[1] == 1'b1 & buffer_head_q[2] == 1'b1) ? data2_in :
                                     (buffer_bypass[1] == 1'b1 & buffer_head_q[1] == 1'b1) ? data3_in :
                                     (buffer_bypass[2] == 1'b1 & buffer_head_q[3] == 1'b1) ? data2_in :
                                     (buffer_bypass[2] == 1'b1 & buffer_head_q[2] == 1'b1) ? data3_in :
                                     buffer_data_q[3];
      end

   if (i > 3)
   begin : bi
       buffer_data_din[i] <= (buffer_bypass[0] == 1'b1 & buffer_head_q[i] == 1'b1) ? data0_in :
                                  (buffer_bypass[0] == 1'b1 & buffer_head_q[i - 1] == 1'b1) ? data1_in :
                                  (buffer_bypass[0] == 1'b1 & buffer_head_q[i - 2] == 1'b1) ? data2_in :
                                  (buffer_bypass[0] == 1'b1 & buffer_head_q[i - 3] == 1'b1) ? data3_in :
                                  (buffer_bypass[1] == 1'b1 & buffer_head_q[i] == 1'b1) ? data1_in :
                                  (buffer_bypass[1] == 1'b1 & buffer_head_q[i - 1] == 1'b1) ? data2_in :
                                  (buffer_bypass[1] == 1'b1 & buffer_head_q[i - 2] == 1'b1) ? data3_in :
                                  (buffer_bypass[2] == 1'b1 & buffer_head_q[i] == 1'b1) ? data2_in :
                                  (buffer_bypass[2] == 1'b1 & buffer_head_q[i - 1] == 1'b1) ? data3_in :
                                  buffer_data_q[i];
   end

if (i < `IBUFF_DEPTH)
begin : ba

           buffer_data_d[i] <= buffer_data_din[i];

           buffer_array_d[i * IBUFF_WIDTH:(i + 1) * IBUFF_WIDTH - 1] <= buffer_data_d[i];
           buffer_data_q[i] <= buffer_array_q[i * IBUFF_WIDTH:(i + 1) * IBUFF_WIDTH - 1];

end
end
end
end
endgenerate



// reconstruct buffer data
generate
begin : xhdl2
genvar                             i;
for (i = 0; i <= `IBUFF_DEPTH - 1; i = i + 1)
begin : buff0_mux
always @( * )
begin
if (i == 0)
  begin : m0
     buffer0_data_muxed[0] <= (buffer_tail_q[0] ? buffer_data_q[0] : 0 );
end
if (i >= 1)
  begin : mi
     buffer0_data_muxed[i] <= (buffer_tail_q[i] ? buffer_data_q[i] : 0 ) | buffer0_data_muxed[i - 1];
end
end
end
end
endgenerate
assign buffer0_ibuff_data = buffer0_data_muxed[`IBUFF_DEPTH - 1];

generate
begin : xhdl3
genvar                             i;
for (i = 0; i <= `IBUFF_DEPTH - 1; i = i + 1)
begin : buff1_mux
always @( * )
begin
if (i == 0)
  begin : m0
     buffer1_data_muxed[0] <= (buffer_tail_q[`IBUFF_DEPTH - 1] ? buffer_data_q[0] : 0 );
end
if (i >= 1)
  begin : mi
     buffer1_data_muxed[i] <= (buffer_tail_q[i-1] ? buffer_data_q[i] : 0 ) | buffer1_data_muxed[i - 1];
end
end
end
end
endgenerate
assign buffer1_ibuff_data = buffer1_data_muxed[`IBUFF_DEPTH - 1];

assign buffer0_data = buffer0_ibuff_data[0:IBUFF_WIDTH - 1];
assign buffer1_data = buffer1_ibuff_data[0:IBUFF_WIDTH - 1];

//--------------------------------------
// watermarks
//--------------------------------------

generate
begin : xhdl4
   genvar                             i;
   for (i = 0; i <= ((`IBUFF_DEPTH/4) - 1); i = i + 1)
   begin : fetch_gen
      assign ib_ic_need_fetch[i] = (~buffer_valid_q[i * 4]);
   end
end
endgenerate

//--------------------------------------
// incoming stall
//--------------------------------------

// iu4 pipe has valid instr(iu4_0_valid_q) but there is backpressure
// (id_ib_iu4_stall == iu5_stall)
assign iu4_stall = iu4_0_valid_q & id_ib_iu4_stall;

//--------------------------------------
// stall buffer
//--------------------------------------
// in case of stall, instr from ibuffer is temporarily saved in stall buffer
// stall buffer nomarlly accept every instruction from ibuffer,
// but it stops accepting when processor keep stalling.
// please note that stall buffer saving is only meaningful when instruction is
// valid. that is why valid_int is used for stall_d calculation.
// please note that uc_swap only occurs when data_out is microcode op.
// so it is not normal case.
//
assign valid_int[0] = buffer_valid_q[0] | iu3_val[0] | stall_q[0];
assign valid_int[1] = (stall_q[0] == 1'b0) ? (buffer_valid_q[0] & iu3_val[0]) | buffer_valid_q[1] | iu3_val[1] | stall_q[1] :
                      buffer_valid_q[0] | iu3_val[0] | stall_q[1];

assign valid_out[0] = valid_int[0];
assign valid_out[1] = valid_int[1] & (~uc_hole[1]) & (~error_hole[1]);

assign stall_d[0] = (uc_swap == 1'b0) ? valid_int[0] & (iu4_stall | uc_stall) & (~buffer_valid_flush) :
                    (stall_q[1] == 1'b0) ? valid_int[1] & (iu4_stall | uc_stall) & (~buffer_valid_flush) :
                    (~buffer_valid_flush);
assign stall_d[1] = (uc_swap == 1'b0) ? valid_int[1] & (iu4_stall | uc_stall) & (~buffer_valid_flush) :
                    1'b0;

assign stall_buffer_act[0] = (~stall_q[0]) | uc_swap;
assign stall_buffer_act[1] = (~stall_q[1]);

assign stall_buffer_data0_d = (uc_swap == 1'b1) ? data1_out :
                              (buffer_valid_q[0] == 1'b1) ? buffer0_data :
                              fast_data0;

assign stall_buffer_data1_d = (buffer_valid_q[1] == 1'b1 & stall_q[0] == 1'b0) ? buffer1_data :
                              (buffer_valid_q[0] == 1'b1 & stall_q[0] == 1'b1) ? buffer0_data :
                              (buffer_valid_q[0] == 1'b0 & stall_q[0] == 1'b0) ? fast_data1 :
                              fast_data0;

assign data0_out = (stall_q[0] == 1'b1) ? stall_buffer_data0_q :
                   stall_buffer_data0_d;

assign data1_out = (stall_q[1] == 1'b1) ? stall_buffer_data1_q :
                   stall_buffer_data1_d;

//--------------------------------------
// branch fusion
//--------------------------------------

assign fuse_en[0] = data0_out[57];
assign fuse_en[1] = iu4_1_instr_q[57];

assign iu4_0_fuse_val_din = (uc_select == 1'b1) ? 1'b0 :
                            (fuse_en[1] == 1'b1 & iu4_1_valid_q == 1'b1) ? 1'b1 :
                            (iu4_0_fuse_val_q == 1'b1 & iu4_0_valid_q == 1'b1) ? 1'b0 :
                            iu4_0_fuse_val_q;

assign iu4_0_fuse_data_din = (fuse_en[1] == 1'b1 & iu4_1_valid_q == 1'b1) ? iu4_1_instr_q[0:31] :
                             iu4_0_fuse_data_q;

assign iu4_1_fuse_val_din = fuse_en[0] & valid_out[0] & (~(uc_select));

assign iu4_1_fuse_data_din = data0_out[0:31];

//--------------------------------------
// ucode muxing
//--------------------------------------

// if "will be issued" instruction is ucode instruction(flag bit is in 56th
// bit)
// Then temporarily swap to ucode mode.
assign ucode_out[0] = data0_out[56];
assign ucode_out[1] = data1_out[56];

assign iu4_uc_mode_din[0] = (cp_flush_into_uc_delay_q[1] == 1'b1) ? 1'b1 :
                            (|(uc_ib_val) == 1'b1 & uc_ib_done == 1'b1 & uc_select == 1'b1) ? 1'b0 :
                            (valid_out[0] == 1'b1 & ucode_out[0] == 1'b1 & uc_select == 1'b0) ? 1'b1 :
                            iu4_uc_mode_q[0];

assign iu4_uc_mode_din[1] = (cp_flush_into_uc_delay_q[1] == 1'b1) ? 1'b0 :
                            (|(uc_ib_val) == 1'b1 & uc_ib_done == 1'b1 & uc_select == 1'b1) ? 1'b0 :
                            (valid_out[1] == 1'b1 & ucode_out[1] == 1'b1 & uc_select == 1'b0) ? 1'b1 :
                            iu4_uc_mode_q[1];

assign uc_stall = iu4_uc_mode_d[0] | iu4_uc_mode_q[0] | iu4_uc_mode_q[1];
assign uc_select = |(iu4_uc_mode_q[0:1]);
assign uc_hole[0] = 1'b0;
assign uc_hole[1] = valid_out[0] & ucode_out[0];
assign uc_swap = iu4_0_ucode_q[1] & uc_select_d & (~uc_select_q);		//ucode in instr0, and ucode select edge detect
assign uc_select_d = uc_select;

assign ib_uc_rdy = uc_select & (~iu4_stall);
assign ib_rm_rdy = (~iu4_stall);

//--------------------------------------
// erat error single instruction issue
//--------------------------------------

assign error0_out[0:2] = data0_out[53:55];
assign error1_out[0:2] = data1_out[53:55];

assign error_hole[0] = 1'b0;
assign error_hole[1] = valid_out[0] & error0_out == 3'b111;

assign iu4_0_valid_din = (uc_select == 1'b1) ? uc_ib_val[0] :
                         valid_out[0] | rm_ib_iu3_val;
			     assign iu4_0_instr_din = (uc_select == 1'b1) ? {uc_ib_instr0[0:31], {(`IBUFF_INSTR_WIDTH-32){1'b0}}} :
                         (rm_ib_iu3_val == 1'b1) ? {rm_ib_iu3_instr[0:31], {(`IBUFF_INSTR_WIDTH-32){1'b0}}} :
                         data0_out[0:`IBUFF_INSTR_WIDTH - 1];
assign iu4_0_bta_din = data0_out[`IBUFF_INSTR_WIDTH:`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH - 1];
assign iu4_0_ifar_din = (uc_select == 1'b1) ? uc_ib_ifar0[62 - `EFF_IFAR_WIDTH:61] :
                        data0_out[`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH:IDATA_WIDTH - 1];
assign iu4_0_ucode_ext_din = (uc_select ? uc_ib_ext0 : 0 ) | (rm_ib_iu3_val ? rm_ib_iu3_instr[32:35] : 0 );

assign iu4_0_ucode_din[0] = uc_select;
assign iu4_0_ucode_din[1] = (~uc_select) & valid_out[0] & ucode_out[0];
assign iu4_0_ucode_din[2] = uc_select & uc_ib_done & uc_ib_val[0] & (~uc_ib_val[1]);
assign iu4_0_isram_din = rm_ib_iu3_val;

assign iu4_1_valid_din = (uc_select == 1'b1) ? uc_ib_val[1] :
                         valid_out[1];
assign iu4_1_instr_din = (uc_select == 1'b1) ? {uc_ib_instr1[0:31], {(`IBUFF_INSTR_WIDTH-32){1'b0}}} :
                         data1_out[0:`IBUFF_INSTR_WIDTH - 1];
assign iu4_1_bta_din = data1_out[`IBUFF_INSTR_WIDTH:`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH - 1];
assign iu4_1_ifar_din = (uc_select == 1'b1) ? uc_ib_ifar1[62 - `EFF_IFAR_WIDTH:61] :
                        data1_out[`IBUFF_INSTR_WIDTH + `EFF_IFAR_WIDTH:IDATA_WIDTH - 1];
assign iu4_1_ucode_ext_din = (uc_select ? uc_ib_ext1 : 0 );

assign iu4_1_ucode_din[0] = uc_select;
assign iu4_1_ucode_din[1] = (~uc_select) & valid_out[1] & ucode_out[1];
assign iu4_1_ucode_din[2] = uc_select & uc_ib_done & uc_ib_val[1];
assign iu4_1_isram_din = 1'b0;

//--------------------------------------
// output latches
//--------------------------------------


always @(iu4_stall or buffer_valid_flush or iu4_uc_mode_din or iu4_0_valid_din or iu4_0_instr_din or iu4_0_bta_din or iu4_0_ifar_din or iu4_0_ucode_din or iu4_0_ucode_ext_din or iu4_0_isram_din or iu4_0_fuse_val_din or iu4_0_fuse_data_din or iu4_1_valid_din or iu4_1_instr_din or iu4_1_bta_din or iu4_1_ifar_din or iu4_1_ucode_din or iu4_1_ucode_ext_din or iu4_1_isram_din or iu4_1_fuse_val_din or iu4_1_fuse_data_din or iu4_uc_mode_q or iu4_0_valid_q or iu4_0_instr_q or iu4_0_bta_q or iu4_0_ifar_q or iu4_0_ucode_q or iu4_0_ucode_ext_q or iu4_0_isram_q or iu4_0_fuse_val_q or iu4_0_fuse_data_q or iu4_1_valid_q or iu4_1_instr_q or iu4_1_bta_q or iu4_1_ifar_q or iu4_1_ucode_q or iu4_1_ucode_ext_q or iu4_1_isram_q or iu4_1_fuse_val_q or iu4_1_fuse_data_q)
begin: iu4_proc

   iu4_uc_mode_d <= iu4_uc_mode_din;
   iu4_0_valid_d <= iu4_0_valid_din;
   iu4_0_instr_d <= iu4_0_instr_din;
   iu4_0_bta_d <= iu4_0_bta_din;
   iu4_0_ifar_d <= iu4_0_ifar_din;
   iu4_0_ucode_d <= iu4_0_ucode_din;
   iu4_0_ucode_ext_d <= iu4_0_ucode_ext_din;
   iu4_0_isram_d <= iu4_0_isram_din;
   iu4_0_fuse_val_d <= iu4_0_fuse_val_din;
   iu4_0_fuse_data_d <= iu4_0_fuse_data_din;
   iu4_1_valid_d <= iu4_1_valid_din;
   iu4_1_instr_d <= iu4_1_instr_din;
   iu4_1_bta_d <= iu4_1_bta_din;
   iu4_1_ifar_d <= iu4_1_ifar_din;
   iu4_1_ucode_d <= iu4_1_ucode_din;
   iu4_1_ucode_ext_d <= iu4_1_ucode_ext_din;
   iu4_1_isram_d <= iu4_1_isram_din;
   iu4_1_fuse_val_d <= iu4_1_fuse_val_din;
   iu4_1_fuse_data_d <= iu4_1_fuse_data_din;

   if (iu4_stall == 1'b1)
   begin
      iu4_uc_mode_d <= iu4_uc_mode_q;
      iu4_0_valid_d <= iu4_0_valid_q;
      iu4_0_instr_d <= iu4_0_instr_q;
      iu4_0_bta_d <= iu4_0_bta_q;
      iu4_0_ifar_d <= iu4_0_ifar_q;
      iu4_0_ucode_d <= iu4_0_ucode_q;
      iu4_0_ucode_ext_d <= iu4_0_ucode_ext_q;
      iu4_0_isram_d <= iu4_0_isram_q;
      iu4_0_fuse_val_d <= iu4_0_fuse_val_q;
      iu4_0_fuse_data_d <= iu4_0_fuse_data_q;
      iu4_1_valid_d <= iu4_1_valid_q;
      iu4_1_instr_d <= iu4_1_instr_q;
      iu4_1_bta_d <= iu4_1_bta_q;
      iu4_1_ifar_d <= iu4_1_ifar_q;
      iu4_1_ucode_d <= iu4_1_ucode_q;
      iu4_1_ucode_ext_d <= iu4_1_ucode_ext_q;
      iu4_1_isram_d <= iu4_1_isram_q;
      iu4_1_fuse_val_d <= iu4_1_fuse_val_q;
      iu4_1_fuse_data_d <= iu4_1_fuse_data_q;
   end

   if (buffer_valid_flush == 1'b1)
   begin
      iu4_uc_mode_d <= 2'b0;
      iu4_0_valid_d <= 1'b0;
      iu4_1_valid_d <= 1'b0;
      iu4_0_fuse_val_d <= 1'b0;
      iu4_1_fuse_val_d <= 1'b0;
   end

end

//--------------------------------------
// instruction output
//--------------------------------------

assign ib_id_iu4_0_valid = iu4_0_valid_q;
assign ib_id_iu4_0_instr = iu4_0_instr_q;
assign ib_id_iu4_0_ucode = iu4_0_ucode_q;
assign ib_id_iu4_0_ucode_ext = iu4_0_ucode_ext_q;
assign ib_id_iu4_0_bta = iu4_0_bta_q;
assign ib_id_iu4_0_ifar = iu4_0_ifar_q;
assign ib_id_iu4_0_isram = iu4_0_isram_q;
assign ib_id_iu4_0_fuse_val = iu4_0_fuse_val_q;
assign ib_id_iu4_0_fuse_data = iu4_0_fuse_data_q;

assign ib_id_iu4_1_valid = iu4_1_valid_q;
assign ib_id_iu4_1_instr = iu4_1_instr_q;
assign ib_id_iu4_1_ucode = iu4_1_ucode_q;
assign ib_id_iu4_1_ucode_ext = iu4_1_ucode_ext_q;
assign ib_id_iu4_1_bta = iu4_1_bta_q;
assign ib_id_iu4_1_ifar = iu4_1_ifar_q;
assign ib_id_iu4_1_isram = iu4_1_isram_q;
assign ib_id_iu4_1_fuse_val = iu4_1_fuse_val_q;
assign ib_id_iu4_1_fuse_data = iu4_1_fuse_data_q;

//---------------------------------------------------------------------
// Latches
//---------------------------------------------------------------------


tri_rlmlatch_p #(.INIT(0)) uc_select_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[uc_select_offset]),
   .scout(sov[uc_select_offset]),
   .din(uc_select_d),
   .dout(uc_select_q)
);


tri_rlmreg_p #(.WIDTH(`IBUFF_DEPTH), .INIT(0)) buffer_valid_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(buffer_valid_act),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[buffer_valid_offset:buffer_valid_offset + `IBUFF_DEPTH - 1]),
   .scout(sov[buffer_valid_offset:buffer_valid_offset + `IBUFF_DEPTH - 1]),
   .din(buffer_valid_d),
   .dout(buffer_valid_q[0:`IBUFF_DEPTH - 1])
);


tri_rlmreg_p #(.WIDTH(`IBUFF_DEPTH), .INIT(1)) buffer_head_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(buffer_head_act),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[buffer_head_offset:buffer_head_offset + `IBUFF_DEPTH - 1]),
   .scout(sov[buffer_head_offset:buffer_head_offset + `IBUFF_DEPTH - 1]),
   .din(buffer_head_d),
   .dout(buffer_head_q[0:`IBUFF_DEPTH - 1])
);


tri_rlmreg_p #(.WIDTH(`IBUFF_DEPTH), .INIT(1)) buffer_tail_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(buffer_tail_act),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[buffer_tail_offset:buffer_tail_offset + `IBUFF_DEPTH - 1]),
   .scout(sov[buffer_tail_offset:buffer_tail_offset + `IBUFF_DEPTH - 1]),
   .din(buffer_tail_d),
   .dout(buffer_tail_q[0:`IBUFF_DEPTH - 1])
);


tri_rlmreg_p #(.WIDTH((`IBUFF_DEPTH*IBUFF_WIDTH-1+1)), .INIT(0)) buffer_array_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu3_val[0]),		//tiup,
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[buffer_array_offset:buffer_array_offset + (`IBUFF_DEPTH*IBUFF_WIDTH-1+1) - 1]),
   .scout(sov[buffer_array_offset:buffer_array_offset + (`IBUFF_DEPTH*IBUFF_WIDTH-1+1) - 1]),
   .din(buffer_array_d),
   .dout(buffer_array_q)
);


tri_rlmreg_p #(.WIDTH(IDATA_WIDTH), .INIT(0)) stall_buffer_data0_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(stall_buffer_act[0]),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[stall_buffer_data0_offset:stall_buffer_data0_offset + IDATA_WIDTH - 1]),
   .scout(sov[stall_buffer_data0_offset:stall_buffer_data0_offset + IDATA_WIDTH - 1]),
   .din(stall_buffer_data0_d),
   .dout(stall_buffer_data0_q)
);


tri_rlmreg_p #(.WIDTH(IDATA_WIDTH), .INIT(0)) stall_buffer_data1_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(stall_buffer_act[1]),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[stall_buffer_data1_offset:stall_buffer_data1_offset + IDATA_WIDTH - 1]),
   .scout(sov[stall_buffer_data1_offset:stall_buffer_data1_offset + IDATA_WIDTH - 1]),
   .din(stall_buffer_data1_d),
   .dout(stall_buffer_data1_q)
);


tri_rlmreg_p #(.WIDTH(2), .INIT(0)) stall_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[stall_offset:stall_offset + 2 - 1]),
   .scout(sov[stall_offset:stall_offset + 2 - 1]),
   .din(stall_d),
   .dout(stall_q)
);


tri_rlmreg_p #(.WIDTH(2), .INIT(0)) iu4_uc_mode_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_uc_mode_offset:iu4_uc_mode_offset + 2 - 1]),
   .scout(sov[iu4_uc_mode_offset:iu4_uc_mode_offset + 2 - 1]),
   .din(iu4_uc_mode_d),
   .dout(iu4_uc_mode_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_0_valid_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_valid_offset]),
   .scout(sov[iu4_0_valid_offset]),
   .din(iu4_0_valid_d),
   .dout(iu4_0_valid_q)
);


tri_rlmreg_p #(.WIDTH(`IBUFF_INSTR_WIDTH), .INIT(0)) iu4_0_instr_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_instr_offset:iu4_0_instr_offset + `IBUFF_INSTR_WIDTH - 1]),
   .scout(sov[iu4_0_instr_offset:iu4_0_instr_offset + `IBUFF_INSTR_WIDTH - 1]),
   .din(iu4_0_instr_d),
   .dout(iu4_0_instr_q)
);


tri_rlmreg_p #(.WIDTH((`EFF_IFAR_WIDTH)), .INIT(0)) iu4_0_ifar_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_ifar_offset:iu4_0_ifar_offset + (`EFF_IFAR_WIDTH) - 1]),
   .scout(sov[iu4_0_ifar_offset:iu4_0_ifar_offset + (`EFF_IFAR_WIDTH) - 1]),
   .din(iu4_0_ifar_d),
   .dout(iu4_0_ifar_q)
);


tri_rlmreg_p #(.WIDTH((`EFF_IFAR_WIDTH)), .INIT(0)) iu4_0_bta_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_bta_offset:iu4_0_bta_offset + (`EFF_IFAR_WIDTH) - 1]),
   .scout(sov[iu4_0_bta_offset:iu4_0_bta_offset + (`EFF_IFAR_WIDTH) - 1]),
   .din(iu4_0_bta_d),
   .dout(iu4_0_bta_q)
);


tri_rlmreg_p #(.WIDTH(3), .INIT(0)) iu4_0_ucode_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_ucode_offset:iu4_0_ucode_offset + 3 - 1]),
   .scout(sov[iu4_0_ucode_offset:iu4_0_ucode_offset + 3 - 1]),
   .din(iu4_0_ucode_d),
   .dout(iu4_0_ucode_q)
);


tri_rlmreg_p #(.WIDTH(4), .INIT(0)) iu4_0_ucode_ext_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_ucode_ext_offset:iu4_0_ucode_ext_offset + 4 - 1]),
   .scout(sov[iu4_0_ucode_ext_offset:iu4_0_ucode_ext_offset + 4 - 1]),
   .din(iu4_0_ucode_ext_d),
   .dout(iu4_0_ucode_ext_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_0_isram_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_isram_offset]),
   .scout(sov[iu4_0_isram_offset]),
   .din(iu4_0_isram_d),
   .dout(iu4_0_isram_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_0_fuse_val_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_fuse_val_offset]),
   .scout(sov[iu4_0_fuse_val_offset]),
   .din(iu4_0_fuse_val_d),
   .dout(iu4_0_fuse_val_q)
);


tri_rlmreg_p #(.WIDTH(32), .INIT(0)) iu4_0_fuse_data_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_0_fuse_val_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_0_fuse_data_offset:iu4_0_fuse_data_offset + 32 - 1]),
   .scout(sov[iu4_0_fuse_data_offset:iu4_0_fuse_data_offset + 32 - 1]),
   .din(iu4_0_fuse_data_d),
   .dout(iu4_0_fuse_data_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_1_valid_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_valid_offset]),
   .scout(sov[iu4_1_valid_offset]),
   .din(iu4_1_valid_d),
   .dout(iu4_1_valid_q)
);


tri_rlmreg_p #(.WIDTH(`IBUFF_INSTR_WIDTH), .INIT(0)) iu4_1_instr_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_instr_offset:iu4_1_instr_offset + `IBUFF_INSTR_WIDTH - 1]),
   .scout(sov[iu4_1_instr_offset:iu4_1_instr_offset + `IBUFF_INSTR_WIDTH - 1]),
   .din(iu4_1_instr_d),
   .dout(iu4_1_instr_q)
);


tri_rlmreg_p #(.WIDTH((`EFF_IFAR_WIDTH)), .INIT(0)) iu4_1_ifar_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_ifar_offset:iu4_1_ifar_offset + (`EFF_IFAR_WIDTH) - 1]),
   .scout(sov[iu4_1_ifar_offset:iu4_1_ifar_offset + (`EFF_IFAR_WIDTH) - 1]),
   .din(iu4_1_ifar_d),
   .dout(iu4_1_ifar_q)
);


tri_rlmreg_p #(.WIDTH((`EFF_IFAR_WIDTH)), .INIT(0)) iu4_1_bta_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_bta_offset:iu4_1_bta_offset + (`EFF_IFAR_WIDTH) - 1]),
   .scout(sov[iu4_1_bta_offset:iu4_1_bta_offset + (`EFF_IFAR_WIDTH) - 1]),
   .din(iu4_1_bta_d),
   .dout(iu4_1_bta_q)
);


tri_rlmreg_p #(.WIDTH(3), .INIT(0)) iu4_1_ucode_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_ucode_offset:iu4_1_ucode_offset + 3 - 1]),
   .scout(sov[iu4_1_ucode_offset:iu4_1_ucode_offset + 3 - 1]),
   .din(iu4_1_ucode_d),
   .dout(iu4_1_ucode_q)
);


tri_rlmreg_p #(.WIDTH(4), .INIT(0)) iu4_1_ucode_ext_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_ucode_ext_offset:iu4_1_ucode_ext_offset + 4 - 1]),
   .scout(sov[iu4_1_ucode_ext_offset:iu4_1_ucode_ext_offset + 4 - 1]),
   .din(iu4_1_ucode_ext_d),
   .dout(iu4_1_ucode_ext_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_1_isram_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_valid_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_isram_offset]),
   .scout(sov[iu4_1_isram_offset]),
   .din(iu4_1_isram_d),
   .dout(iu4_1_isram_q)
);


tri_rlmlatch_p #(.INIT(0)) iu4_1_fuse_val_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_fuse_val_offset]),
   .scout(sov[iu4_1_fuse_val_offset]),
   .din(iu4_1_fuse_val_d),
   .dout(iu4_1_fuse_val_q)
);


tri_rlmreg_p #(.WIDTH(32), .INIT(0)) iu4_1_fuse_data_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(iu4_1_fuse_val_din),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[iu4_1_fuse_data_offset:iu4_1_fuse_data_offset + 32 - 1]),
   .scout(sov[iu4_1_fuse_data_offset:iu4_1_fuse_data_offset + 32 - 1]),
   .din(iu4_1_fuse_data_d),
   .dout(iu4_1_fuse_data_q)
);


tri_rlmlatch_p #(.INIT(0)) cp_flush_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[cp_flush_offset]),
   .scout(sov[cp_flush_offset]),
   .din(cp_flush_d),
   .dout(cp_flush_q)
);


tri_rlmlatch_p #(.INIT(0)) br_iu_redirect_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[br_iu_redirect_offset]),
   .scout(sov[br_iu_redirect_offset]),
   .din(br_iu_redirect_d),
   .dout(br_iu_redirect_q)
);


tri_rlmreg_p #(.WIDTH(2), .INIT(0)) cp_flush_into_uc_latch(
   .vd(vdd),
   .gd(gnd),
   .nclk(nclk),
   .act(tiup),
   .thold_b(pc_iu_func_sl_thold_0_b),
   .sg(pc_iu_sg_0),
   .force_t(force_t),
   .delay_lclkr(delay_lclkr),
   .mpw1_b(mpw1_b),
   .mpw2_b(mpw2_b),
   .d_mode(d_mode),
   .scin(siv[cp_flush_into_uc_offset:cp_flush_into_uc_offset + 2 - 1]),
   .scout(sov[cp_flush_into_uc_offset:cp_flush_into_uc_offset + 2 - 1]),
   .din(cp_flush_into_uc_delay_d),
   .dout(cp_flush_into_uc_delay_q)
);


//-----------------------------------------------
// pervasive
//-----------------------------------------------


   tri_plat #(.WIDTH(2)) perv_2to1_reg(
      .vd(vdd),
      .gd(gnd),
      .nclk(nclk),
      .flush(tc_ac_ccflush_dc),
      .din({pc_iu_func_sl_thold_2,pc_iu_sg_2}),
      .q({pc_iu_func_sl_thold_1,pc_iu_sg_1})
   );


   tri_plat #(.WIDTH(2)) perv_1to0_reg(
      .vd(vdd),
      .gd(gnd),
      .nclk(nclk),
      .flush(tc_ac_ccflush_dc),
      .din({pc_iu_func_sl_thold_1,pc_iu_sg_1}),
      .q({pc_iu_func_sl_thold_0,pc_iu_sg_0})
   );


tri_lcbor  perv_lcbor(
   .clkoff_b(clkoff_b),
   .thold(pc_iu_func_sl_thold_0),
   .sg(pc_iu_sg_0),
   .act_dis(act_dis),
   .force_t(force_t),
   .thold_b(pc_iu_func_sl_thold_0_b)
);

//---------------------------------------------------------------------
// Scan
//---------------------------------------------------------------------
assign siv[0:scan_right] = {sov[1:scan_right], scan_in};
assign scan_out = sov[0];


endmodule
