First off this is how I did this might not be the best way 
probably not the only way and by no means the supported way of doing this 
use this at your own Risk 

 
this project is to feed filament from a btt smart sensor out side the machien to the tool head inside the machine 
this can be done with or with out filament switch at the tool head I have macros for both here 

I used the Annex engineering belay extruder sync sensor 
https://github.com/Annex-Engineering/Belay

in my setup I am using a sherpa Mini with filament switch and ECAS fitting found here 
https://www.printables.com/model/999921-sherpa-mini-with-ecas-and-integrated-filament-sens
but any extruder with a fitting to secure the ptfe tube will work I ahve used 
cnc mini sherpas and regular mini sherpas with a mount for  a m10 fitting to hold the ptfe 

you are going to need to source about 3-5 input pins and a stepper driver pre tool you want to add this too
2 inputs for the the btt smart sensor this is optional you could a simple filament switch or a button to trigger the loading 
1 input for the Belay sensor 
and 1 optional button for unloading (I used a 6mm tactile button)
I used a spare older 8 bit board I had with 5 stepper drivers 
also a option input for a filament sensor on your tool board 

you will need a extruder with a fitting to secure the ptfe for each tool aswell 
I used BMG/bmgclones and I did test a sherpa mini with a fitting but found the bmg was able to push the filament faster down the ptfe 
but you could deffinatly use a sherpa mini or any of the dirivtitaves I will inclue my test mount <img width="1520" height="572" alt="feeder_sherpa_render" src="https://github.com/user-attachments/assets/ec337426-976b-4a8f-a5af-d3ac2d130023" />

![bmg_mount_with_switch](https://github.com/user-attachments/assets/ceddc7ac-c21a-4ae3-b110-e4dad918c97b)
<img width="1520" height="572" alt="render2" src="https://github.com/user-attachments/assets/208eef66-0dfd-441f-aee9-2c5f13220a5b" />
![bmg mounted](https://github.com/user-attachments/assets/b1e858cc-95d6-4a64-8627-015e9aba537e)

there is a fair bit of configuring 
I will include some of my files as examples 

I have also documented this build on the stealth changer discord 
https://discordapp.com/channels/1226846451028725821/1401147182639481004
if you have any questions this is probably the best place to ask

My macro's require you to have a purge bucket and brush 
as well as a working Clean nozzle macro 

after adding the relivant setting for Belay and dynamic macros to your printer cfg 
you will need to add 
  LOAD_ANY_TOOL T=0 S=30 D=1360  T being the tool number S is the speed in mm/s and D is the max distance 

[filament_switch_sensor filament_sensor_tool0]
switch_pin: ^MMB:PC15
pause_on_runout: FALSE
runout_gcode:
  M118 Runout sensor  tool0 reports: Runout
  SET_GCODE_VARIABLE MACRO=tool0 VARIABLE=filament_consumed VALUE=1
insert_gcode:
  M118 Runout sensor tool0 reports: Filament Detected
  SET_GCODE_VARIABLE MACRO=tool0 VARIABLE=filament_consumed VALUE=0
  LOAD_ANY_TOOL T=0 S=30 D=1360
