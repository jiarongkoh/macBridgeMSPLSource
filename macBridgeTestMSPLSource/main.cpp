//
//  main.cpp
//  macBridgeTest
//
//  Created by liuhui on 2019/3/28.
//  Copyright © 2019 lh. All rights reserved.
//

#include <iostream>
#include "TestObject-C-Interface.h"
#include "TestObject.h"
#include <unistd.h>
int main(int argc, const char * argv[]) {
    // insert code here...
    std::cout << "Hello, World!\n";
    TypeLock *tl = new TypeLock();
    tl->testFunction(12);
    usleep(5*1000*1000);
    
    tl->testFunction2();
    
    usleep(5*1000*1000);
//    char *a = (char*)(0x111);
//    free(a);
    
    return 0;
}
