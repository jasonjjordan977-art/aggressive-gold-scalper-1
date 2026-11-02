import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
export default function TabLayout() { return <Tabs screenOptions={{ headerShown:false, tabBarActiveTintColor:'#D7B66C',tabBarInactiveTintColor:'#79858A',tabBarLabelStyle:{fontFamily:'Manrope_600SemiBold',fontSize:9,marginTop:3},tabBarStyle:{backgroundColor:'#101416',borderTopColor:'#263033',paddingTop:10,height:75,paddingBottom:16} }}>
<Tabs.Screen name="index" options={{title:'Terminal',tabBarIcon:({color,size})=><Ionicons name="grid-outline" color={typeof color === "string" ? color : "#D7B66C"} size={size-3}/>}}/>
<Tabs.Screen name="explore" options={{title:'Activity',tabBarIcon:({color,size})=><Ionicons name="pulse-outline" color={typeof color === "string" ? color : "#D7B66C"} size={size-3}/>}}/>
<Tabs.Screen name="bridge" options={{title:'Bridge',tabBarIcon:({color,size})=><Ionicons name="link-outline" color={typeof color === "string" ? color : "#D7B66C"} size={size-3}/>}}/>
<Tabs.Screen name="settings" options={{title:'Settings',tabBarIcon:({color,size})=><Ionicons name="options-outline" color={typeof color === "string" ? color : "#D7B66C"} size={size-3}/>}}/>
</Tabs>; }
