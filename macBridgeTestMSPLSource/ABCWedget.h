//
//  ABCWedget.h
//  macBridgeTest
//
//  Created by liuhui on 2019/3/28.
//  Copyright © 2019 lh. All rights reserved.
//


//#ifdef __OBJC__
//@class ABCWidget;
//#else
//typedef struct objc_object ABCWidget;
//#endif

#ifdef __OBJC__
#define OBJC_CLASS(name) @class name
#else
#define OBJC_CLASS(name) typedef struct objc_object name
#endif

OBJC_CLASS(ABCWidget);

namespace abc
{
    class Widget
    {
        ABCWidget* wrapped;
    public:
        Widget();
        ~Widget();
        void Reticulate();
    };
}
