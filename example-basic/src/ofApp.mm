#include "ofApp.h"



void logSIMD(const simd::float4x4 &matrix)
{
    std::stringstream output;
    int columnCount = sizeof(matrix.columns) / sizeof(matrix.columns[0]);
    for (int column = 0; column < columnCount; column++) {
        int rowCount = sizeof(matrix.columns[column]) / sizeof(matrix.columns[column][0]);
        for (int row = 0; row < rowCount; row++) {
            output << std::setfill(' ') << std::setw(9) << matrix.columns[column][row];
            output << ' ';
        }
        output << std::endl;
    }
    output << std::endl;
}

//--------------------------------------------------------------
ofApp :: ofApp (ARSession * session){
    this->session = session;
    cout << "creating ofApp" << endl;
}

ofApp::ofApp(){}

//--------------------------------------------------------------
ofApp :: ~ofApp () {
    cout << "destroying ofApp" << endl;
}

//--------------------------------------------------------------
void ofApp::setup() {
    ofBackground(127);
    
    img.load("OpenFrameworks.png");
    
    int fontSize = 8;
    if (ofxiOSGetOFWindow()->isRetinaSupportedOnDevice())
        fontSize *= 2;
    
    font.load("fonts/mono0755.ttf", fontSize);
    
    processor = ARProcessor::create(session);
    processor->setup();
    
}



//--------------------------------------------------------------
void ofApp::update(){
    
    processor->update();
    
}

//--------------------------------------------------------------
void ofApp::draw() {
    ofEnableAlphaBlending();
    
    ofDisableDepthTest();
    processor->draw();
    ofEnableDepthTest();
    
    
    if (session.currentFrame){
        if (session.currentFrame.camera){
           
            camera.begin();
            processor->setARCameraMatrices();
            
            for (int i = 0; i < session.currentFrame.anchors.count; i++){
                ARAnchor * anchor = session.currentFrame.anchors[i];
                ofPushMatrix();
                ofMatrix4x4 mat = ARCommon::convert<matrix_float4x4, ofMatrix4x4>(anchor.transform);
                ofMultMatrix(mat);
                
                ofSetColor(255);
                ofRotate(90,0,0,1);
                
                img.draw(-0.025 / 2, -0.025 / 2,0.025,0.025);
                
                
                ofPopMatrix();
            }
          
            camera.end();
        }
        
    }
    ofDisableDepthTest();
    // ========== DEBUG STUFF ============= //
    processor->debugInfo.drawDebugInformation(font);
    


    /*
     for (int i = 0; i < mats.size(); i++){
     ofPushMatrix();
     ofMatrix4x4 mat;
     mat.set(mats[i].columns[0].x, mats[i].columns[0].y,mats[i].columns[0].z,mats[i].columns[0].w,
     mats[i].columns[1].x, mats[i].columns[1].y,mats[i].columns[1].z,mats[i].columns[1].w,
     mats[i].columns[2].x, mats[i].columns[2].y,mats[i].columns[2].z,mats[i].columns[2].w,
     mats[i].columns[3].x, mats[i].columns[3].y,mats[i].columns[3].z,mats[i].columns[3].w);
     ofMultMatrix(mat);
     
     ofSetColor(255);
     ofRotate(90,0,0,1);
     
     float aspect = ARCommon::getNativeAspectRatio();
     img.draw(-aspect/8,-0.125,aspect/4,0.25);
     
     
     ofPopMatrix();
     }
     
     */
    
}

//--------------------------------------------------------------
void ofApp::exit() {
    //
}

//--------------------------------------------------------------
void ofApp::touchDown(ofTouchEventArgs &touch){
    if (session.currentFrame){
        ARFrame *currentFrame = [session currentFrame];
        
        matrix_float4x4 translation = matrix_identity_float4x4;
        translation.columns[3].z = -0.2;
        matrix_float4x4 transform = matrix_multiply(currentFrame.camera.transform, translation);
        
        // Add a new anchor to the session
        ARAnchor *anchor = [[ARAnchor alloc] initWithTransform:transform];
        
        [session addAnchor:anchor];
    }
}

//--------------------------------------------------------------
void ofApp::touchMoved(ofTouchEventArgs &touch){
    
}

//--------------------------------------------------------------
void ofApp::touchUp(ofTouchEventArgs &touch){
    
}

//--------------------------------------------------------------
void ofApp::touchDoubleTap(ofTouchEventArgs &touch){
    
}

//--------------------------------------------------------------
void ofApp::lostFocus(){
    
}

//--------------------------------------------------------------
void ofApp::gotFocus(){
    
}

//--------------------------------------------------------------
void ofApp::gotMemoryWarning(){
    
}

//--------------------------------------------------------------
void ofApp::deviceOrientationChanged(int newOrientation){
    processor->updateDeviceInterfaceOrientation();
    processor->deviceOrientationChanged();
    
}


//--------------------------------------------------------------
void ofApp::touchCancelled(ofTouchEventArgs& args){
    
}


