// this de-obfuscated version by Davide Della Casa
// original obfuscated version by Yusuke Endoh

// Changed to SDL graphics and all-integer calculations by Matthias Koch, 2021
// clang -O3 -Wall -W -pedantic -fno-strict-aliasing pixelfall-walls.c -o pixelfall-walls -lm -lSDL

#include <stdio.h>
#include <unistd.h>
#include <math.h>
#include <SDL/SDL.h>

// ----------------------------------------------------------------------------
//   Graphics primitives
// ----------------------------------------------------------------------------

void putpixel (SDL_Surface *canvas, int x, int y, Uint32 pixel)
{
  Uint32 *ptr = (Uint32 *) canvas->pixels;
  int lineoffset = y * (canvas->pitch) / 4;
  int pixelpos = lineoffset + x;
  ptr[pixelpos] = pixel;
}

Uint32 getpixel (SDL_Surface *canvas, int x, int y)
{
  Uint32 *ptr = (Uint32 *) canvas->pixels;
  int lineoffset = y * (canvas->pitch) / 4;
  int pixelpos = lineoffset + x;
  return ptr[pixelpos];
}

void clrscr  (SDL_Surface *canvas)
{
  Uint32 *ptr = (Uint32 *) canvas->pixels;
  memset(ptr, 0, canvas->w * canvas->h * 4);
}

// ----------------------------------------------------------------------------
//   Simulation coefficients
// ----------------------------------------------------------------------------

// #define FIXPOINT 4294967296
// #define FIXPOINT 65536
#define FIXPOINT 256 // For 32 bit integer range of everything

int32_t gravity     = 0.4 * FIXPOINT;
int32_t pressure    = 4; //   * FIXPOINT;
int32_t viscosity   = 8; //   * FIXPOINT;
int32_t temperature = 9; //   * FIXPOINT;

// ----------------------------------------------------------------------------
//   Particle definition
// ----------------------------------------------------------------------------

#define MAXIMUM_PARTICLES 8192

#define SKALIERUNG 6

struct Particle {
    int32_t xPos;
    int32_t yPos;

    int32_t temperature;
    int32_t xForce;
    int32_t yForce;
    int32_t xVelocity;
    int32_t yVelocity;

    int wallflag;
    int visible;
} particles[MAXIMUM_PARTICLES];

int    totalOfParticles;

void newparticle(int x, int y, int wall)
{
    particles[totalOfParticles].xPos = FIXPOINT * x;
    particles[totalOfParticles].yPos = FIXPOINT * y;

    particles[totalOfParticles].wallflag = wall;
    particles[totalOfParticles].temperature = 0;
    particles[totalOfParticles].xVelocity = 0;
    particles[totalOfParticles].yVelocity = 0;
    particles[totalOfParticles].xForce = 0;
    particles[totalOfParticles].yForce = 0;
    particles[totalOfParticles].visible = 1;

    totalOfParticles += 1;
}

// ----------------------------------------------------------------------------
//   Fluid simulation
// ----------------------------------------------------------------------------

int main()
{

  // ----------------------------------------------------------
  // Create environment

  int x, y;

  // Add water

  for (y=20; y < 40; y++) for (x = 20; x < 40; x++) newparticle(x, y, 0);

  // Add walls

  // Replaced by bounding the field, see (*)

   for (y=10; y < 12; y++) for (x = 10; x < 52; x++) newparticle(x, y, 1);
   for (y=50; y < 52; y++) for (x = 10; x < 52; x++) newparticle(x, y, 1);

   for (y=10; y < 50; y++) for (x = 10; x < 12; x++) newparticle(x, y, 1);
   for (y=10; y < 50; y++) for (x = 50; x < 52; x++) newparticle(x, y, 1);

  // Stirring rod

  for (y=10; y < 30; y++) for (x = 30; x < 32; x++) newparticle(x, y, 1);

  // ----------------------------------------------------------
  // Time for simulation

  int frame = 0;

  SDL_Event e;
  SDL_Surface *s = SDL_SetVideoMode(640,480,32,0);

    do {

        int p1, p2;

        // Iterate over every pair of particles to calculate the densities
        for (p1 = 0; p1 < totalOfParticles; p1++)

        {
            // temperature of "wall" particles is high, other particles will bounce off them.
            particles[p1].temperature = particles[p1].wallflag * temperature * FIXPOINT;

            if (!particles[p1].wallflag)
            for (p2 = 0; p2 < totalOfParticles; p2++){

                int32_t xParticleDistance = (particles[p1].xPos - particles[p2].xPos);
                int32_t yParticleDistance = (particles[p1].yPos - particles[p2].yPos);

                int32_t PartInt = xParticleDistance * xParticleDistance + yParticleDistance * yParticleDistance;

                // Temperature is updated only if particles are close enough
                if ( PartInt < 4 * FIXPOINT * FIXPOINT)
                    particles[p1].temperature += PartInt/4/FIXPOINT - sqrt(PartInt) + FIXPOINT;
            }
        }

        // Iterate over every pair of particles to calculate the forces

        for (p1 = 0; p1 < totalOfParticles; p1++)
        if (!particles[p1].wallflag)
        {

            particles[p1].xForce = gravity * sin(frame/100.0);
            particles[p1].yForce = gravity * cos(frame/100.0);

            for (p2 = 0; p2 < totalOfParticles; p2++){

                int32_t xParticleDistance = (particles[p1].xPos - particles[p2].xPos);
                int32_t yParticleDistance = (particles[p1].yPos - particles[p2].yPos);

                int32_t PartInt = xParticleDistance * xParticleDistance + yParticleDistance * yParticleDistance;

                if ( PartInt < 4 * FIXPOINT * FIXPOINT){

                    particles[p1].xForce += (sqrt(PartInt) / 2 - FIXPOINT) * (xParticleDistance * (3 * FIXPOINT - particles[p1].temperature - particles[p2].temperature) / FIXPOINT * pressure + (particles[p1].xVelocity - particles[p2].xVelocity) * viscosity) / particles[p1].temperature;
                    particles[p1].yForce += (sqrt(PartInt) / 2 - FIXPOINT) * (yParticleDistance * (3 * FIXPOINT - particles[p1].temperature - particles[p2].temperature) / FIXPOINT * pressure + (particles[p1].yVelocity - particles[p2].yVelocity) * viscosity) / particles[p1].temperature;

                }
            }
        }

        for (p1 = 0; p1 < totalOfParticles; p1++) {

            if (!particles[p1].wallflag) {

                // This is the newtonian mechanics part: knowing the force vector acting on each
                // particle, we accelerate the particle (see the change in velocity).

                // Force affects velocity
                particles[p1].xVelocity += particles[p1].xForce / 10;
                particles[p1].yVelocity += particles[p1].yForce / 10;

                // If particle would hit bounds given this velocity, chill and reflect it (*)
                // if (  (particles[p1].xVelocity + particles[p1].xPos) < 12 * FIXPOINT || (particles[p1].xVelocity + particles[p1].xPos) > 50 * FIXPOINT  )
                // {
                //     particles[p1].xVelocity = -particles[p1].xVelocity / 2;
                // }
                //
                // if (  (particles[p1].yVelocity + particles[p1].yPos) < 12 * FIXPOINT || (particles[p1].yVelocity + particles[p1].yPos) > 50 * FIXPOINT  )
                // {
                //     particles[p1].yVelocity = -particles[p1].yVelocity / 2;
                // }

                // Velocity affects position
                particles[p1].xPos += particles[p1].xVelocity;
                particles[p1].yPos += particles[p1].yVelocity;

                // Keep particles bounded all the time (*)
                // if (  particles[p1].xPos < 12*FIXPOINT ) particles[p1].xPos = 12*FIXPOINT;
                // if (  particles[p1].xPos > 50*FIXPOINT ) particles[p1].xPos = 50*FIXPOINT;
                // if (  particles[p1].yPos < 12*FIXPOINT ) particles[p1].yPos = 12*FIXPOINT;
                // if (  particles[p1].yPos > 50*FIXPOINT ) particles[p1].yPos = 50*FIXPOINT;

            }
        }

    clrscr(s);

    int currvis = 0;

    for (p1 = 0; p1 < totalOfParticles; p1++) if (particles[p1].visible) { // Draw pixel for each element

      // More sparkling by removing fractional bits
      // x = particles[p1].xPos / FIXPOINT * SKALIERUNG;
      // y = particles[p1].yPos / FIXPOINT * SKALIERUNG;

      // More flowing position with fractional bits
      x = SKALIERUNG * particles[p1].xPos / FIXPOINT;
      y = SKALIERUNG * particles[p1].yPos / FIXPOINT;

      if (0 <= x && x < 640 && 0 <= y && y < 480)
      {
          currvis++;
          for (int sx = 0; sx < SKALIERUNG; sx++)
          for (int sy = 0; sy < SKALIERUNG; sy++)
          putpixel(s, x+sx, y+sy, (particles[p1].wallflag ? 0x00FFFFFF : ((0x00004040 + getpixel(s, x+sx, y+sy)) & 0x0000FFFF) /* | (p1 & 0xFF) << 16 */)); // White walls, blue water
      }
      else particles[p1].visible = 0;
    }

    printf("Frame: %i, Visible: %i\n", frame, currvis);
    frame++;

    SDL_Flip(s);
    SDL_PollEvent(&e);

        // don't peg the cpu, be merciful, pause a little.
        usleep(12321);

    } while (!((e.type == SDL_QUIT) || e.type == SDL_KEYDOWN)); // End with keypress

  return(0);
}
