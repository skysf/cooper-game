import { Engine } from '@babylonjs/core/Engines/engine';
import { Scene } from '@babylonjs/core/scene';
import { FreeCamera } from '@babylonjs/core/Cameras/freeCamera';
import { Camera } from '@babylonjs/core/Cameras/camera';
import { DirectionalLight } from '@babylonjs/core/Lights/directionalLight';
import { HemisphericLight } from '@babylonjs/core/Lights/hemisphericLight';
import { Vector3,Vector4 } from '@babylonjs/core/Maths/math.vector';
import { Color3,Color4 } from '@babylonjs/core/Maths/math.color';
import { ImportMeshAsync } from '@babylonjs/core/Loading/sceneLoader';
import '@babylonjs/loaders/glTF/2.0';
import '@babylonjs/loaders/glTF/glTFFileLoader';
import { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';

type Palette={sky:number[],fog:number[],fogNear:number,fogFar:number,sun:number[],direct:number,ambient:number};
type Preset={drops:number,speed:number,darken:number,wetRoad:number,wetRock:number};
type State=Preset & {x:number,y:number,z:number,pitch:number,yaw:number,time:number,wet:number};
declare const Wood:{
 loaded:Promise<void>,scene:{render:{width:number,height:number,horizontalFov:number,near:number,far:number},sunDirection:number[],shelter:{x:number,z:number,width:number,depth:number},weather:{clear:Palette,rain:Palette,base:Preset,storm:Preset}},
 ready():void,step():State,frame():void,fail(err:unknown):void
};

function makeRain(scene:Scene,count:number){
 const mesh=new Mesh('Rain',scene), data=new VertexData();
 const positions:number[]=[],indices:number[]=[],seeds:number[]=[];
 const hash=(i:number,k:number)=>{const n=Math.sin((i+1)*k)*43758.5453;return n-Math.floor(n);};
 for(let i=0;i<count;i++){
   const seed=[hash(i,12.9898),hash(i,78.233),hash(i,37.719)];
   for(const [x,y] of [[-.006,-.09],[.006,-.09],[.006,.09],[-.006,.09]]){
     positions.push(x+y*.11,y,0);seeds.push(...seed);
   }
   const a=i*4;indices.push(a,a+1,a+2,a,a+2,a+3);
 }
 data.positions=positions;data.indices=indices;data.applyToMesh(mesh);
 mesh.setVerticesData('seed',seeds,false,3);
 const material=new ShaderMaterial('Rain streak',scene,{
   vertexSource:`precision highp float;attribute vec3 position,seed;uniform mat4 world,worldViewProjection;uniform vec4 roof;uniform float fallen;void main(){vec3 offset=vec3((seed.x-.5)*16.,mod(seed.y*10.-fallen,10.)-2.,(seed.z-.5)*16.);vec4 local=vec4(position+offset,1.);vec3 p=(world*local).xyz;bool inside=all(lessThan(abs(p.xz-roof.xy),roof.zw)) && p.y<2.7;gl_Position=inside?vec4(2.,2.,2.,1.):worldViewProjection*local;}`,
   fragmentSource:`precision highp float;uniform float opacity;void main(){gl_FragColor=vec4(.71,.81,.86,.44*opacity);}`
 },{attributes:['position','seed'],uniforms:['world','worldViewProjection','roof','fallen','opacity'],needAlphaBlending:true});
 const hut=Wood.scene.shelter;material.setVector4('roof',new Vector4(hut.x,hut.z,hut.width/2,hut.depth/2));
 material.backFaceCulling=false;material.disableDepthWrite=true;mesh.material=material;mesh.alwaysSelectAsActiveMesh=true;
 return {mesh,material};
}

async function main(){
 await Wood.loaded;
 const canvas=document.querySelector<HTMLCanvasElement>('#canvas')!;
 const {render,weather,sunDirection}=Wood.scene;
 canvas.width=render.width;canvas.height=render.height;
 const gl=canvas.getContext('webgl2',{antialias:false,alpha:false,stencil:true});
 if(!gl)throw Error('需要 WebGL 2');
 const engine=new Engine(gl,false,{adaptToDeviceRatio:false,stencil:true,doNotHandleContextLost:false});
 engine.setSize(render.width,render.height,true);
 const scene=new Scene(engine);scene.useRightHandedSystem=true;
 scene.imageProcessingConfiguration.toneMappingEnabled=false;
 scene.fogMode=Scene.FOGMODE_LINEAR;
 const camera=new FreeCamera('Observer',Vector3.Zero(),scene);
 camera.inputs.clear();camera.fovMode=Camera.FOVMODE_HORIZONTAL_FIXED;
 camera.fov=render.horizontalFov*Math.PI/180;camera.minZ=render.near;camera.maxZ=render.far;
 const sun=new DirectionalLight('Sun',Vector3.FromArray(sunDirection).normalize(),scene);
 const sky=new HemisphericLight('Skylight',Vector3.Up(),scene);
 sky.groundColor=Color3.White();sky.specular=Color3.Black();
 await ImportMeshAsync('/shared/woodland.glb',scene);
 const surfaces=scene.materials.filter((m):m is PBRMaterial=>m instanceof PBRMaterial && ['mud','rock'].includes(m.name))
   .map(m=>({m,col:m.albedoColor.clone(),rough:m.roughness??1}));
 const rain=makeRain(scene,Wood.step().drops);
 const mix=(a:number,b:number,t:number)=>a+(b-a)*t;
 function blend(a:number[],b:number[],t:number){return Color3.Lerp(Color3.FromArray(a),Color3.FromArray(b),t);}
 let lastWet=-1;
 function update(){
   const s=Wood.step(),wet=s.wet,cp=Math.cos(s.pitch);
   camera.position.set(s.x,s.y,s.z);
   camera.setTarget(new Vector3(s.x+Math.sin(s.yaw)*cp,s.y+Math.sin(s.pitch),s.z-Math.cos(s.yaw)*cp));
   if(lastWet!==wet){
     const a=weather.clear,b=weather.rain;
     scene.clearColor=Color4.FromColor3(blend(a.sky,b.sky,wet),1);
     scene.fogColor=blend(a.fog,b.fog,wet);scene.fogStart=mix(a.fogNear,b.fogNear,wet);scene.fogEnd=mix(a.fogFar,b.fogFar,wet);
     sun.diffuse=blend(a.sun,b.sun,wet);sun.intensity=mix(a.direct,b.direct,wet);
     sky.intensity=mix(a.ambient,b.ambient,wet);
     for(const {m,col,rough} of surfaces){m.albedoColor=col.scale(1-wet*s.darken);m.roughness=mix(rough,m.name==='mud'?s.wetRoad:s.wetRock,wet);}
     rain.mesh.setEnabled(wet>0);rain.material.setFloat('opacity',wet);lastWet=wet;
   }
   rain.mesh.position.copyFrom(camera.position);rain.mesh.rotation.y=-s.yaw;
   rain.material.setFloat('fallen',s.time*s.speed);
 }
 update();await scene.whenReadyAsync();
 let first=true;
 engine.runRenderLoop(()=>{update();scene.render();if(first){first=false;Wood.ready();}Wood.frame();});
}
main().catch(err=>Wood.fail(err));
