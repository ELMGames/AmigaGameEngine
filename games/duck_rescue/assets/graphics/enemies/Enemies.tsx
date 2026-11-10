<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.12.2" name="Enemies" tilewidth="16" tileheight="16" tilecount="12" columns="4">
 <image source="enemies_16x16.png" width="64" height="48"/>
 <tile id="0" type="enemy_mushroom">
  <properties>
   <property name="speed" type="int" value="1"/>
   <property name="type" type="int" value="1"/>
  </properties>
  <animation>
   <frame tileid="0" duration="150"/>
   <frame tileid="1" duration="150"/>
   <frame tileid="2" duration="150"/>
   <frame tileid="3" duration="150"/>
  </animation>
 </tile>
 <tile id="4" type="enemy_hornet">
  <properties>
   <property name="speed" type="int" value="2"/>
   <property name="type" type="int" value="2"/>
  </properties>
  <animation>
   <frame tileid="4" duration="150"/>
   <frame tileid="5" duration="150"/>
   <frame tileid="6" duration="150"/>
   <frame tileid="7" duration="150"/>
  </animation>
 </tile>
 <tile id="8" type="enemy_hedgehog">
  <properties>
   <property name="speed" type="int" value="1"/>
   <property name="type" type="int" value="3"/>
  </properties>
  <animation>
   <frame tileid="8" duration="150"/>
   <frame tileid="9" duration="150"/>
   <frame tileid="10" duration="150"/>
   <frame tileid="11" duration="150"/>
  </animation>
 </tile>
</tileset>
