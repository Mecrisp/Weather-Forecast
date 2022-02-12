#
#    Weather Forecast - A particle simulator for Lovebyte 2022
#    Copyright (C) 2022  Matthias Koch
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

.option norelax
.option rvc

.section mecrisp, "awx" # Everything is writeable and executable

.global _start
_start:

# -----------------------------------------------------------------------------
#  Memory map
# -----------------------------------------------------------------------------

.equ offset_px,   0 * 4  # Position X
.equ offset_py,   1 * 4  #          Y
.equ offset_vx,   2 * 4  # Velocity X
.equ offset_vy,   3 * 4  #          Y
.equ offset_fx,   4 * 4  # Force    X
.equ offset_fy,   5 * 4  #          Y
.equ offset_temp, 6 * 4  # Temperature
.equ offset_wall, 7 * 4  # Flag: Free particle if zero, else wall particle

.equ particle_size, 8*4  # Size of one particle in memory

# -----------------------------------------------------------------------------
#  Define particle properties
# -----------------------------------------------------------------------------

.equ SCALE, 6            # How many fractional bits for fixpoint calculations
.equ ONE,   1<<SCALE     # Integer "one" in fixpoint notation

# Factors defined as shifts:

.equ PRESSURE,    2 # = 2^2 = 4
.equ VISCOSITY,   3 # = 2^3 = 8
.equ MASS,        3 # = 2^-3 = 1/8

# Factors used directly:

.equ TEMPERATURE, 9
.equ GRAVITY, ONE >> 1

# -----------------------------------------------------------------------------
#  Prepare 1920x1080x32bpp framebuffer
# -----------------------------------------------------------------------------

framebuffer_open:
   li x10, -100                # Directory: AT_FDCWD
   la x11, device              # Device to open
   li x12, 2                   # O_RDWR
   li x17, 56                  # "openat"
   ecall                       # open("/dev/fb0", O_RDWR)
framebuffer_mmap:
   mv x14, x10                 # --> File descriptor
   la x10, 0                   # Device to open
   li x11, 1920 * 1080 * 4     # Length
   li x12, 3                   # PROT_READ | PROT_WRITE
   li x13, 1                   # MAP_SHARED
   #  x14                      # File descriptor
   li x15, 0                   # Offset
   li x17, 222                 # "mmap"
   ecall                       # mmap2(NULL, Length, PROT_READ|PROT_WRITE, MAP_SHARED, FD, 0)

   # Mapped address of framebuffer is now in x10.

   # See https://jborza.com/post/2021-05-11-riscv-linux-sysc.jals/
   # for sysc.jal numbers

   mv x3, x10
   la x31, particles
   c.jal clrscr

# -----------------------------------------------------------------------------
particle_initialisation:

   mv x4, x31  # Start of particle table
   li x5, 4095 # Maximum value for DAC output

   li x11, 55  # Magic value to get a cycle that looks like a sun.
   mv x9, x11  # Try 97 instead for twelve small circles!
   li x12, 0

mandala:

      addi x8, x11, 130     # Move and scale the mandala cycle
      slli x8, x8, SCALE-2  # suitable for full-screen size
      sw x8, offset_px(x31)

      addi x8, x12, 130
      slli x8, x8, SCALE-2
      sw x8, offset_py(x31)

      li x8, TEMPERATURE * ONE # All particles are walls at the beginning
      sw x8, offset_wall(x31)

      addi x31, x31, particle_size

mandala_next_point_on_cycle:

      c.jal mandala_cycle  # Calculate next point on the closed rotation cycle
      srai x14, x12, 1     # Magic values 0xDDB3D743 and 0x40000000 for
      c.add  x11, x14      # a rotation of 1/12 of full circle
      c.jal mandala_cycle  #

   bne x11, x9, mandala   # Check if x coordinate is back to start value
   bne x12, zero, mandala # Check if y coordinate is back to start value

# -----------------------------------------------------------------------------
wave_initialisation:

   li x25, 0      # Initial sine
   li x26, 128    # Initial cosine
   li x27, -166   # Initial frame counter

# -----------------------------------------------------------------------------
#  Notes on register usage while in animation loop:
#
#   x3: Constant DAC_BASE
#   x4: Constant start of particle table
#   x5: Constant maximum DAC value
#
#   x8: Scratch
#   x9: Scratch
#  x10: Distance, x-component
#  x11: Distance, y-component
#  x12: Outer particle loop counter
#  x13: Inner particle loop counter for pair interactions
#  x14: Scratch
#  x15: Scratch
#
#  x23: Scratch in sqrt
#  x24: dx^2 + dy^2
#
#  x25: Sine   for waves
#  x26: Cosine for waves
#  x27: Frame counter
#
#  x31: Constant end of particle table
#
# -----------------------------------------------------------------------------
animation_loop: # Main loop for animation.

  addi x27, x27, 1 # Increase frame counter, used for rain and cloud effect

  c.jal clrscr

  li x14, 1024     # Do not continue forever
  bge x27, x14, bye

# -----------------------------------------------------------------------------
   mv x12, x31 # Start at the end of the particle list.
               # Going backward and forward in turn saves subsequent initialisations of outer loop pointer.

temperature:   # Temperature exchange for every pair of particles

   addi x12, x12, -particle_size # Traverse particle list backwards

      lw x8, offset_wall(x12)
      bne x8, zero, temperature_skip_wall # Walls keep their default temperature, no need to update

      mv x13, x4

temperature_pair_loop:
         c.jal xy_distance                   # Calculate distance for this pair of particles
         bge x24, x15, temperature_skip_pair # Temperature is updated only if particles are close enough

         sw zero, offset_wall(x13) # Wall changes into moveable particle when hit for the first time by rain

         srai x10, x24, SCALE+2   # x10 = (dx^2+dy^2)/4
         c.jal sqrt               # x14 = sqrt(dx^2 + dy^2)
         sub x10, x10, x14        # x10 = (dx^2+dy^2)/4 - sqrt(dx^2+dy^2)
         addi x10, x10, ONE       # x10 = (dx^2+dy^2)/4 - sqrt(dx^2+dy^2) - 1

         add x8, x8, x10          # Integrate temperature over pairs of particles

temperature_skip_pair:
      addi x13, x13, particle_size
      bne x13, x31, temperature_pair_loop # Finished when reaching end of particle list

temperature_skip_wall:
      sw x8, offset_temp(x12)
      c.jal paintparticlex12 # Display current outer loop particle while doing calculations

   bne x12, x4, temperature  # Finished when reaching start of particle list

# -----------------------------------------------------------------------------
force:

      c.jal paintparticlex12    # Display current outer loop particle while doing calculations
      lw x15, offset_wall(x12)  # Do not update force for walls. Initial force is zero, these shall not move.
      bne x15, zero, force_skip_wall

      lw x9, offset_temp(x12)   # Fetch temperature of current particle
                                # Initialise integration of force vector for inner loop:
      srai x29, x25, 3          # Scaled sine used as x-component of force causes waves
      li x30, GRAVITY           # Constant gravity as y-component of force

      slli x15, x27, 31-8       # For half the time, gravity with waves is replaced by
      blt zero, x15, 1f         # a rotating force to generate clouds and
      srai x30, x26, 3          # cool splashes when gravity kicks in again
1:

      mv x13, x4 # Inner loop starts at the beginning of the particle table

force_pair_loop:
         c.jal xy_distance              # Calculate distance for this pair of particles
         bge x24, x15, force_skip_pair  # Force is updated only if particles are close enough for interaction

         c.jal sqrt                     # x14 = sqrt(dx^2 + dy^2)
         srai x14, x14, 1               # x14 = sqrt(dx^2 + dy^2)/2
         addi x24, x14, -ONE            # x24 = sqrt(dx^2 + dy^2)/2 - 1

         li x14, 3*ONE                  # x14 =  3
         lw x15,  offset_temp(x13)
         sub x14, x14, x9               # x14 =  3 - temperature(x12)
         sub x14, x14, x15              # x14 =  3 - temperature(x12) - temperature(x13)
         slli x14, x14, PRESSURE        # x14 = (3 - temperature(x12) - temperature(x13)) * pressure

         lw x15, offset_vx(x12)         # Load x-components of velocity for
         lw x8,  offset_vx(x13)         # viscosity calculations
         c.jal force_x                  #
         add x29, x29, x10              # Integrate x-component of force

         mv x10, x11                    # Switch dx register over to dy value for handling y component now
         lw x15, offset_vy(x12)         # Load y-components of velocity for
         lw x8,  offset_vy(x13)         # viscosity calculations
         c.jal force_x
         add x30, x30, x10              # Integrate y-component of force

force_skip_pair:
      addi x13, x13, particle_size
      bne x13, x31, force_pair_loop    # Finished when reaching end of particle list

      sw x29, offset_fx(x12)           # Store freshly integrated
      sw x30, offset_fy(x12)           # force vector for outer loop particle

force_skip_wall:
   addi x12, x12, particle_size
   bne x12, x31, force          # Finished when reaching end of particle list

# -----------------------------------------------------------------------------
velocity:

   addi x12, x12, -(particle_size-4)  # Traverse particle list backwards

      c.jal velocity_x                   # Offset is for handling y components here

      addi x12, x12, -4                  # Switch offset to handle x components
      c.jal velocity_x                   # Offset is at the beginning of the particle now

      c.jal paintparticlex12             # Paint it!

   bne x12, x4, velocity  # Finished when reaching start of particle list

# -----------------------------------------------------------------------------
waves:

  srai x15, x25, 4           # Minsky integer circle algorithm
  sub  x26, x26, x15         # x25 and x26 approximate sine and cosine
  srai x15, x26, 4           # These are mixed with gravity components
  add  x25, x25, x15         # for waves and clouds

# -----------------------------------------------------------------------------
rain:

  blt x27, zero, animation_loop # Rain begins when framecounter, which starts negative, reaches zero

  andi x15, x27, 0x07       # One new raindrop for every eight frame
  bne x15, zero, animation_loop

  slli x15, x27, 31-8       # Rainfall happens on framecounter for 2^8=256 particles. We have less particles in use, so rain stops intermittently.
  srli x15, x15, 31-9  - 5  # Calculate offset into particle table, particle size is 8*4 = 2^5 bytes.
  add x15, x15, x4          # Add start address of particle table

  sw zero, offset_py(x15)   # Set particle to top of image, keep x-position
  sw zero, offset_wall(x15) # Remove wall property for this particle

  j animation_loop

# -----------------------------------------------------------------------------
sqrt: # Integer square root, algorithm from "Hacker's Delight". x14 = sqrt(x24)
# -----------------------------------------------------------------------------
   li     x15, 0x40000000
   c.li   x14, 0
1: or     x23, x15, x14
   c.srli x14, 1
   bltu   x24, x23, 2f
   sub    x24, x24, x23
   c.or   x14, x15
2: c.srli x15, 2
   bne    x15, zero, 1b
   ret

# -----------------------------------------------------------------------------
xy_distance: # Calculates squared distance for a pair of particles
# -----------------------------------------------------------------------------
   lw x10, offset_px(x12)
   lw x11, offset_py(x12)
   lw x15, offset_px(x13)
   lw x14, offset_py(x13)

   sub x10, x10, x15  # x-Distance
   sub x11, x11, x14  # y-Distance
   mul x15, x10, x10  # x-Distance^2
   mul x14, x11, x11  # y-Distance^2
   add x24, x15, x14  # Sum of squared distances

   li x15, 4*ONE*ONE  # Load constant for particle collision detection
   ret

# -----------------------------------------------------------------------------
force_x: # Handles one component of force update taking care of viscosity and particle temperature.
# -----------------------------------------------------------------------------
   mul x10, x10, x14         #  x10 = dx * (3 - temperature(x12) - temperature(x13)) * pressure
   srai x10, x10, SCALE      #  Fixpoint scaling adjustment shift

   sub x15, x15, x8          #  x15 =  velocity_x(x12) - velocity_x(x13)
   slli x15, x15, VISCOSITY  #  x15 = (velocity_x(x12) - velocity_x(x13)) * viscosity

   add x10, x10, x15         #  x10 = dx * (3 - temperature(x12) - temperature(x13)) * pressure + (velocity_x(x12) - velocity_x(x13)) * viscosity
   mul x10, x10, x24         #  x10 = ( ... ) * (distance/2 - 1)
   div x10, x10, x9          #  x10 = ( ... ) * (distance/2 - 1) / temperature(x12)
   ret

# -----------------------------------------------------------------------------
velocity_x: # Handles one component of velocity and position update
            # This is called twice, with offset to x12 for y component
# -----------------------------------------------------------------------------
   lw x10, offset_fx(x12)  # Get force component
   srai x10, x10, MASS     # Force/Mass = Acceleration

   lw x11, offset_vx(x12)  # Get velocity component
   add x11, x11, x10       # Forces change velocity

   lw x10, offset_px(x12)  # Get position component
   add x15, x10, x11       # Expected new position, might be out of bounds

   bltu x15, x5, 1f       # Old position + movement  due to velocity within bounds of 0 and 4095?
      srai x11, x11, 1    # If particle would leave bounds, divide velocity component on this axis by 2
      sub x11, zero, x11  # and change sign to reflect particle on the wall
1:
   sw x11, offset_vx(x12) # Save freshly calculated velocity component
   add x10, x10, x11      # Update position with bounded velocity
   sw x10, offset_px(x12) # Save freshly calculated position
   ret

# -----------------------------------------------------------------------------
mandala_cycle:
# -----------------------------------------------------------------------------
   slli   x14, x11, 2
   li x8, 0xDDB3D743    # Magic value to get closed cycles with 12-symmetry
   mulh   x14, x14, x8
   c.addi x14, 1
   srai   x14, x14, 1
   c.add  x12, x14
   ret

# -----------------------------------------------------------------------------
paintparticlex12:
# -----------------------------------------------------------------------------

  lw x10, 0*4(x12) # offset_px(x12)
  lw x11, 1*4(x12) # offset_py(x12)

   srli x7, x10, 2 # SCALE-4
   srli x8, x11, 2 # SCALE-4

   slli x7, x7, 2
   li x15, 1920*4
   mul x15, x15, x8
   add x7, x7, x15
   add x7, x7, x3

   lw x15, 7*4(x12) # offset_wall(x12)
   beq x15, zero, 2f
     li x15, 0xFFFFFF
     j 3f
2:   li x15, 0x00FFFF
3:

   sw x15, 0(x7)
  ret

# -----------------------------------------------------------------------------
clrscr:
# -----------------------------------------------------------------------------
  mv x14, x3
  li x15, 1920*1080*4
  add x15, x15, x3

1:sw zero, 0(x14)
  addi x14, x14, 4
  bne x14, x15, 1b
  ret

# -----------------------------------------------------------------------------
bye:
# -----------------------------------------------------------------------------
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x17, 93                  # "exit"
    ecall                       # Final system call

device:  .ascii  "/dev/fb0\000"

# -----------------------------------------------------------------------------
.bss
# -----------------------------------------------------------------------------

.equ particles, .

  .rept 256 * 64
  .word 0x00000000
  .endr
