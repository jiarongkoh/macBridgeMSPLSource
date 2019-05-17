//
//  TestObject.h
//  macBridgeTest
//
//  Created by liuhui on 2019/3/28.
//  Copyright © 2019年 liuhui. All rights reserved.
//

#ifndef TestObject_h
#define TestObject_h
#include "TestObject-C-Interface.h"
#include <stdio.h>
class TypeLock{
public:
    void testFunction(int temp){
        printf("Test function\n");
        c_testFunction(temp);
    }
    
    void testFunction2(){
        c_testFunction2();
    }
};


#endif /* TestObject_h */


