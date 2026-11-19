// (C) 2001-2026 Altera Corporation. All rights reserved.
// Your use of Altera Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Altera Program License Subscription 
// Agreement, Altera IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Altera and sold by 
// Altera or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


`timescale 1ps/1ps

module compare_eq #(
    parameter WIDTH=10
) (
    input [WIDTH-1:0]  in_a,
    input [WIDTH-1:0]  in_b,
    output             equal
);

assign equal = (in_a==in_b);

endmodule 
`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "LX4fNUqnOK9YZXada7z4XBduZSVIzRiCZMV68Nw5pi3jGBzEJ7k/q3e2pe2d5ih5hQ+ItbTsv85ur7WT52QvsISuFabvVGM2dFC3XgapA19E935fa4wOMN7g1FoVOeA23o/bx9lzQi1KwtrGAT3WnWAHbOPjvJVj7gDzuux6BsOeHiRy+Hf4CH1XhQbVVKIHvO4RIGSV91Lrvssmc61f/rmN/00diyYUtd7BjtnlFtPTdWP/SiRR08BImVHg7MuS+pg/3lqvCS6oxU58uXbwCqkWw15UEAZhbbHu8IPt5nIWovUwjiWXCsu6bQnGbe9KCMRxji0YNklmqGxCmNzmbA9Xls4ltrm4iZXgIrg0UHj3i4WXbDxrYqgA74qa2lxNuUsOIT2KDx7dHEvG4hZ2y4eVXEptKr71YNnNcgqKS0fhFDpXZOOnGagUu9all51TmzaNmcwSxbuK0egLfzWXCy5UL4ZwD7NeKVsOL+mm8aG4NhvT2lwQVBs7lOgg4nI0N0NImDPCH2PcfwrDjewIgCpd/Na5yw/q+YHYJuiis9BJJtBfkV4F209RTduWE/xUAURRZ7ipZA9HS2pGRNYZ/uL1MPiOKPWcHadJYwt5ELeSSjAnVr6JZrQpjm+Iavfhe8ZjtrDuwouGyd5x//RkG2G29TlrfzoQje2wd71Zg8rZZSrRIj8nB1UvGvKLGlOqklvr0IOsjSXeGpX/iAke5aU9khWELKdhrDgHtCxFFRcaqH94HMYQnk98CrnLDBZjgcir3OEG8ppDSSXsmW0It4cxtt6d2oK3ku/8RX06ea/Nj2Fxst3BcCTDsdo5o2UlgStRcLOuFqpv0LAcoFm4hlLW5mwmdNFlQkaRQlgVbtUSvMiVuv2ZgF0qTPMkVix2C4KMHWDx4IAKPDOt9bwVd0Yz4PDp/djuNT5Jg3PRItxoyIUqlbBTktQEJB+nMF2Pg4ZYFuLhIbvHP39yWcpjHRzPKGepAue/HFPzIFqDDyAgoIwB2AIl1zktPknpLDYC"
`endif