<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.12.2" name="Player" tilewidth="16" tileheight="16" tilecount="4" columns="4">
 <image source="player_idle_64x16.png" width="64" height="16"/>
 <tile id="0" type="player">
  <properties>
   <property name="direction" type="int" value="1"/>
  </properties>
  <animation>
   <frame tileid="0" duration="150"/>
   <frame tileid="1" duration="150"/>
   <frame tileid="2" duration="150"/>
   <frame tileid="3" duration="150"/>
  </animation>
 </tile>
</tileset>
