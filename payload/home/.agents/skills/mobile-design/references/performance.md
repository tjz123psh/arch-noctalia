# Mobile Performance Patterns

优化 React Native 应用性能的综合指南，覆盖渲染、内存、包体积与平台专项优化。

## 渲染性能

### 组件优化

**用 React.memo 处理昂贵组件：**
```typescript
// Prevent unnecessary re-renders
const ExpensiveComponent = React.memo(({ data, onPress }) => {
  return (
    <View>
      <ComplexVisualization data={data} />
      <Button onPress={onPress} />
    </View>
  );
}, (prevProps, nextProps) => {
  // Custom comparison function
  return prevProps.data === nextProps.data &&
         prevProps.onPress === nextProps.onPress;
});
```

**用 useMemo 处理昂贵计算：**
```typescript
function DataScreen({ items }) {
  // Expensive filtering/sorting only runs when items change
  const filteredItems = useMemo(() => {
    return items
      .filter(item => item.active)
      .sort((a, b) => b.date - a.date)
      .slice(0, 20);
  }, [items]);

  return <FlatList data={filteredItems} />;
}
```

**用 useCallback 保持函数引用稳定：**
```typescript
function ParentComponent() {
  const [count, setCount] = useState(0);
  const [text, setText] = useState('');

  // Stable function reference prevents child re-renders
  const handlePress = useCallback(() => {
    setCount(c => c + 1);
  }, []); // Empty deps - function never changes

  return (
    <>
      <Input value={text} onChange={setText} />
      <ExpensiveChild onPress={handlePress} />
    </>
  );
}
```

### 列表渲染

**FlatList 优化：**
```typescript
<FlatList
  data={items}
  renderItem={renderItem}
  keyExtractor={item => item.id} // Stable keys

  // Performance props
  removeClippedSubviews={true} // Unmount off-screen items
  maxToRenderPerBatch={10} // Batch size for rendering
  updateCellsBatchingPeriod={50} // ms between batch renders
  initialNumToRender={10} // Initial items to render
  windowSize={5} // Viewport multiplier for render window

  // Memory optimization
  getItemLayout={(data, index) => ({
    length: ITEM_HEIGHT,
    offset: ITEM_HEIGHT * index,
    index,
  })} // Skip measurement, improve scrolling

  // Optimize item rendering
  renderItem={renderItem} // Use stable function

  // Extract props that don't affect rendering
  extraData={selectedId} // Only re-render when this changes
/>
```

**优化后的列表项组件：**
```typescript
const ListItem = React.memo(({ item, onPress }) => {
  // Avoid creating functions in render
  const handlePress = useCallback(() => {
    onPress(item.id);
  }, [item.id, onPress]);

  return (
    <TouchableOpacity onPress={handlePress}>
      <View style={styles.container}>
        <Image source={{ uri: item.imageUrl }} style={styles.image} />
        <Text>{item.title}</Text>
      </View>
    </TouchableOpacity>
  );
}, (prev, next) => {
  // Custom comparison for re-render control
  return prev.item.id === next.item.id &&
         prev.item.title === next.item.title;
});
```

**自定义布局用 VirtualizedList：**
```typescript
// When FlatList/SectionList aren't flexible enough
<VirtualizedList
  data={items}
  getItem={(data, index) => data[index]}
  getItemCount={data => data.length}
  keyExtractor={item => item.id}
  renderItem={({ item }) => <CustomItem item={item} />}
  initialNumToRender={10}
  maxToRenderPerBatch={10}
/>
```

### 图片优化

**Fast Image 库：**
```typescript
import FastImage from 'react-native-fast-image';

<FastImage
  source={{
    uri: imageUrl,
    priority: FastImage.priority.high,
    cache: FastImage.cacheControl.immutable,
  }}
  resizeMode={FastImage.resizeMode.cover}
  style={styles.image}
/>
```

**图片预取：**
```typescript
// Prefetch images before they're needed
useEffect(() => {
  const urls = items.map(item => item.imageUrl);
  FastImage.preload(urls.map(url => ({ uri: url })));
}, [items]);
```

**按尺寸加载图片：**
```typescript
function OptimizedImage({ url, width, height }) {
  // Load appropriate size based on screen
  const screenScale = PixelRatio.get();
  const targetWidth = width * screenScale;

  // Use image CDN to resize
  const optimizedUrl = `${url}?w=${targetWidth}&q=80`;

  return (
    <FastImage
      source={{ uri: optimizedUrl }}
      style={{ width, height }}
    />
  );
}
```

## 状态管理性能

### 避免 Prop Drilling

**Context API（适合低频更新）：**
```typescript
// Create context with default value
const ThemeContext = createContext({ theme: 'light' });

// Provider at top level
function App() {
  const [theme, setTheme] = useState('light');
  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      <AppContent />
    </ThemeContext.Provider>
  );
}

// Consume anywhere in tree
function DeepComponent() {
  const { theme } = useContext(ThemeContext);
  return <View style={styles[theme]} />;
}
```

**拆分 Context 以避免不必要的重渲染：**
```typescript
// BAD: Single context causes all consumers to re-render
const AppContext = createContext({ user, settings, theme });

// GOOD: Split into separate contexts
const UserContext = createContext(null);
const SettingsContext = createContext(null);
const ThemeContext = createContext(null);
```

**高频更新用 Redux / Zustand：**
```typescript
// Zustand example - simpler than Redux
import create from 'zustand';

const useStore = create((set) => ({
  count: 0,
  increment: () => set((state) => ({ count: state.count + 1 })),
}));

// Component only re-renders when count changes
function Counter() {
  const count = useStore((state) => state.count);
  const increment = useStore((state) => state.increment);

  return <Button onPress={increment} title={`Count: ${count}`} />;
}
```

### 派生状态

**在渲染时计算，而不是在状态变化时计算：**
```typescript
// BAD: Storing derived state
const [items, setItems] = useState([]);
const [filteredItems, setFilteredItems] = useState([]);

useEffect(() => {
  setFilteredItems(items.filter(item => item.active));
}, [items]);

// GOOD: Compute derived state on render
const [items, setItems] = useState([]);
const filteredItems = useMemo(
  () => items.filter(item => item.active),
  [items]
);
```

## 动画性能

### 使用原生驱动

**为动画开启原生驱动：**
```typescript
// Runs on native thread, 60fps even if JS is blocked
Animated.timing(animatedValue, {
  toValue: 1,
  duration: 300,
  useNativeDriver: true, // IMPORTANT
}).start();
```

**支持原生驱动的属性：**
- transform（translateX、translateY、scale、rotate）
- opacity
- backgroundColor（需要 react-native-reanimated）

**不支持原生驱动的属性：**
- 布局属性（width、height、margin、padding）
- color（除非是 reanimated 的 backgroundColor）
- text

### 复杂动效用 Reanimated 2

**完全运行在原生线程：**
```typescript
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
} from 'react-native-reanimated';

function AnimatedComponent() {
  const offset = useSharedValue(0);

  const animatedStyles = useAnimatedStyle(() => {
    return {
      transform: [{ translateX: offset.value }],
    };
  });

  const handlePress = () => {
    offset.value = withTiming(offset.value + 100);
  };

  return (
    <Animated.View style={animatedStyles}>
      <Button onPress={handlePress} />
    </Animated.View>
  );
}
```

### 用 Gesture Handler 获得顺滑交互

**React Native Gesture Handler：**
```typescript
import { GestureDetector, Gesture } from 'react-native-gesture-handler';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
} from 'react-native-reanimated';

function DraggableBox() {
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);

  const pan = Gesture.Pan()
    .onChange((event) => {
      translateX.value += event.changeX;
      translateY.value += event.changeY;
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
    ],
  }));

  return (
    <GestureDetector gesture={pan}>
      <Animated.View style={[styles.box, animatedStyle]} />
    </GestureDetector>
  );
}
```

## 包体积优化

### 代码分割

**页面懒加载：**
```typescript
import React, { lazy, Suspense } from 'react';

// Lazy load heavy screens
const ProfileScreen = lazy(() => import('./screens/ProfileScreen'));
const SettingsScreen = lazy(() => import('./screens/SettingsScreen'));

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Stack.Navigator>
        <Stack.Screen name="Profile" component={ProfileScreen} />
        <Stack.Screen name="Settings" component={SettingsScreen} />
      </Stack.Navigator>
    </Suspense>
  );
}
```

**动态 import：**
```typescript
// Import heavy libraries only when needed
async function handleExport() {
  const XLSX = await import('xlsx');
  const workbook = XLSX.utils.book_new();
  // ... use XLSX
}
```

### 分析包体积

**Metro 打包可视化：**
```bash
# Generate bundle stats
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/index.android.bundle \
  --sourcemap-output /tmp/index.android.bundle.map

# Analyze with source-map-explorer
npx source-map-explorer /tmp/index.android.bundle /tmp/index.android.bundle.map
```

### Tree Shaking

**只导入需要的部分：**
```typescript
// BAD: Imports entire library
import _ from 'lodash';
const result = _.debounce(fn, 300);

// GOOD: Import specific function
import debounce from 'lodash/debounce';
const result = debounce(fn, 300);

// EVEN BETTER: Use built-in or smaller alternatives
// Install lodash-es for better tree shaking
import { debounce } from 'lodash-es';
```

## 内存管理

### useEffect 中的清理

**取消订阅与定时器：**
```typescript
useEffect(() => {
  const subscription = API.subscribe(data => {
    setData(data);
  });

  const timerId = setTimeout(() => {
    // Do something
  }, 5000);

  // Cleanup function
  return () => {
    subscription.unsubscribe();
    clearTimeout(timerId);
  };
}, []);
```

### 事件监听

**移除事件监听：**
```typescript
useEffect(() => {
  const handleKeyboard = (event) => {
    setKeyboardHeight(event.endCoordinates.height);
  };

  const subscription = Keyboard.addListener(
    'keyboardDidShow',
    handleKeyboard
  );

  return () => subscription.remove();
}, []);
```

### 避免异步操作内存泄漏

**取消异步操作：**
```typescript
useEffect(() => {
  let cancelled = false;

  async function fetchData() {
    const response = await fetch(url);
    const data = await response.json();

    // Check if component still mounted
    if (!cancelled) {
      setData(data);
    }
  }

  fetchData();

  return () => {
    cancelled = true;
  };
}, [url]);
```

## 平台专项优化

### Android 专项

**Hermes JavaScript 引擎：**
```javascript
// android/app/build.gradle
project.ext.react = [
    enableHermes: true,  // Faster startup, lower memory
]
```

**收益：**
- 应用启动更快
- 内存占用更低
- APK 体积更小
- 低端设备性能更好

**Release 构建用 ProGuard：**
```gradle
// android/app/build.gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
    }
}
```

### iOS 专项

**Release 中关闭 Flipper：**
```ruby
# ios/Podfile
use_flipper!() # Only for debug builds

# Or conditional:
use_flipper!() if !ENV['PRODUCTION']
```

**图片资源目录（Asset Catalog）：**
```typescript
// Use xcassets for better optimization
<Image source={require('./assets/logo.png')} />

// Automatically uses @2x, @3x based on device
```

## 网络性能

### 缓存策略

**用 React Query 做数据获取：**
```typescript
import { useQuery } from '@tanstack/react-query';

function UserProfile({ userId }) {
  const { data, isLoading } = useQuery({
    queryKey: ['user', userId],
    queryFn: () => fetchUser(userId),
    staleTime: 5 * 60 * 1000, // 5 minutes
    cacheTime: 10 * 60 * 1000, // 10 minutes
  });

  if (isLoading) return <Loading />;
  return <Profile user={data} />;
}
```

**用 AsyncStorage 实现离线优先：**
```typescript
async function fetchWithCache(url, cacheKey) {
  try {
    // Try to get cached data first
    const cached = await AsyncStorage.getItem(cacheKey);
    if (cached) {
      // Return cached data immediately
      return JSON.parse(cached);
    }
  } catch (e) {
    console.log('Cache read failed');
  }

  // Fetch fresh data
  const response = await fetch(url);
  const data = await response.json();

  // Update cache in background
  AsyncStorage.setItem(cacheKey, JSON.stringify(data)).catch(() => {});

  return data;
}
```

### 请求合并

**批量发起请求：**
```typescript
// Instead of multiple requests
const user = await fetch('/api/user/123');
const posts = await fetch('/api/user/123/posts');
const followers = await fetch('/api/user/123/followers');

// Use GraphQL or batch endpoint
const { user, posts, followers } = await fetch('/api/batch', {
  method: 'POST',
  body: JSON.stringify({
    queries: [
      { query: 'user', id: 123 },
      { query: 'posts', userId: 123 },
      { query: 'followers', userId: 123 },
    ],
  }),
});
```

## 性能剖析与监控

### React DevTools Profiler

**测量组件渲染耗时：**
```typescript
import { Profiler } from 'react';

function onRenderCallback(
  id, // the "id" prop of the Profiler tree
  phase, // "mount" or "update"
  actualDuration, // time spent rendering
  baseDuration, // estimated time without memoization
  startTime, // when React began rendering
  commitTime, // when React committed the update
) {
  console.log(`${id} (${phase}) took ${actualDuration}ms`);
}

<Profiler id="UserList" onRender={onRenderCallback}>
  <UserList />
</Profiler>
```

### 性能监控

**开发期用 Flipper：**
- React DevTools
- 网络检查器
- 布局检查器
- 性能监视器

**生产环境监控：**
```typescript
// Install @react-native-firebase/perf
import perf from '@react-native-firebase/perf';

// Trace custom events
const trace = await perf().startTrace('user_profile_load');
await loadUserProfile();
await trace.stop();

// HTTP metrics tracked automatically
```

### 内存剖析

**Android：**
```bash
# Heap dump
adb shell am dumpheap <package_name> /data/local/tmp/heap.hprof
adb pull /data/local/tmp/heap.hprof

# Analyze with Android Studio Memory Profiler
```

**iOS：**
```
# Use Xcode Instruments
# Product → Profile
# Choose "Leaks" or "Allocations"
```

## 性能检查清单

### 发布前

**渲染：**
- [ ] 长列表使用 FlatList
- [ ] 图片已优化并懒加载
- [ ] 昂贵组件已 memo 化
- [ ] 动画使用原生驱动
- [ ] 无不必要的重渲染（用 Profiler 检查）

**包体积：**
- [ ] 已分析大依赖对包体的影响
- [ ] 大页面做了代码分割
- [ ] 移除了未使用的代码
- [ ] 已启用 ProGuard / Hermes（Android）

**网络：**
- [ ] API 调用有恰当的缓存
- [ ] 图片用 FastImage 缓存
- [ ] 关键功能支持离线
- [ ] 尽可能合并请求

**内存：**
- [ ] 已实现 useEffect 清理
- [ ] 已移除事件监听
- [ ] 没有内存泄漏（用 Instruments 剖析）
- [ ] 没有过度使用 AsyncStorage

**平台：**
- [ ] 已启用 Hermes（Android）
- [ ] Release 中已关闭 Flipper
- [ ] 已启用 ProGuard（Android）
- [ ] 资源已优化（iOS）

## 资源

### 工具
- [React DevTools](https://reactnative.dev/docs/debugging#react-devtools)
- [Flipper](https://fbflipper.com/)
- [Reactotron](https://github.com/infinitered/reactotron)
- [Why Did You Render](https://github.com/welldone-software/why-did-you-render)

### 库
- [React Native Reanimated](https://docs.swmansion.com/react-native-reanimated/)
- [React Native Gesture Handler](https://docs.swmansion.com/react-native-gesture-handler/)
- [React Native Fast Image](https://github.com/DylanVann/react-native-fast-image)
- [React Query](https://tanstack.com/query/latest/docs/react/overview)

### 学习资料
- [React Native Performance](https://reactnative.dev/docs/performance)
- [Hermes Engine](https://hermesengine.dev/)
- [Metro Bundler](https://facebook.github.io/metro/)

## 常见性能错误与修复

### 列表渲染与内存

### ❌ 错误：长列表用 ScrollView

**问题：**
```typescript
// BAD: Renders all 1000 items at once
<ScrollView>
  {items.map(item => (
    <ItemCard key={item.id} item={item} />
  ))}
</ScrollView>
```

**影响：**
- 首屏渲染慢
- 内存占用高
- 性能差

**✅ 修复：**
```typescript
// GOOD: Virtualized rendering
<FlatList
  data={items}
  renderItem={({ item }) => <ItemCard item={item} />}
  keyExtractor={item => item.id}
  // Performance optimizations
  removeClippedSubviews={true}
  maxToRenderPerBatch={10}
  windowSize={5}
/>
```

### ❌ 错误：在 renderItem 里创建函数

**问题：**
```typescript
// BAD: New function on every render
<FlatList
  data={items}
  renderItem={({ item }) => (
    <TouchableOpacity onPress={() => handlePress(item)}>
      <Text>{item.name}</Text>
    </TouchableOpacity>
  )}
/>
```

**影响：**
- 每个列表项都新建函数
- 阻碍优化
- 性能差

**✅ 修复：**
```typescript
// GOOD: Stable component with useCallback
const ListItem = React.memo(({ item, onPress }) => {
  const handlePress = useCallback(() => {
    onPress(item.id);
  }, [item.id, onPress]);

  return (
    <TouchableOpacity onPress={handlePress}>
      <Text>{item.name}</Text>
    </TouchableOpacity>
  );
});

<FlatList
  data={items}
  renderItem={({ item }) => <ListItem item={item} onPress={handleItemPress} />}
/>
```

### 图片加载与占位

### ❌ 错误：不优化图片

**问题：**
```typescript
// BAD: Loading full-res 4MB image
<Image
  source={{ uri: 'https://example.com/photo-4000x3000.jpg' }}
  style={{ width: 100, height: 100 }}
/>
```

**影响：**
- 加载慢
- 浪费带宽
- 性能差

**✅ 修复：**
```typescript
// GOOD: Request appropriately sized image
import FastImage from 'react-native-fast-image';

const screenScale = PixelRatio.get();
const imageWidth = 100 * screenScale;

<FastImage
  source={{
    uri: `https://example.com/photo.jpg?w=${imageWidth}&q=80`,
    priority: FastImage.priority.normal,
  }}
  style={{ width: 100, height: 100 }}
  resizeMode={FastImage.resizeMode.cover}
/>
```

### ❌ 错误：没有加载状态

**问题：**
```typescript
// BAD: No placeholder while loading
<Image source={{ uri: imageUrl }} style={styles.image} />
```

**影响：**
- 加载时留白
- 加载完成后布局跳动
- 感知性能差

**✅ 修复：**
```typescript
// GOOD: Skeleton loader or placeholder
import FastImage from 'react-native-fast-image';

<FastImage
  source={{ uri: imageUrl }}
  style={styles.image}
  // Built-in placeholder
  defaultSource={require('./assets/placeholder.png')}
/>

// BETTER: Skeleton with shimmer effect
const [loaded, setLoaded] = useState(false);

<View>
  {!loaded && <SkeletonPlaceholder />}
  <FastImage
    source={{ uri: imageUrl }}
    style={[styles.image, !loaded && { position: 'absolute' }]}
    onLoadEnd={() => setLoaded(true)}
  />
</View>
```

### 动画

### ❌ 错误：不使用原生驱动

**问题：**
```typescript
// BAD: Animated on JS thread (laggy if JS busy)
Animated.timing(fadeAnim, {
  toValue: 1,
  duration: 300,
  useNativeDriver: false,
}).start();
```

**影响：**
- 动画卡顿
- JS 忙时掉帧
- 体验差

**✅ 修复：**
```typescript
// GOOD: Runs on native thread (smooth)
Animated.timing(fadeAnim, {
  toValue: 1,
  duration: 300,
  useNativeDriver: true, // Works for opacity, transform
}).start();

// BETTER: Use Reanimated for complex animations
import Animated, { withTiming } from 'react-native-reanimated';

opacity.value = withTiming(1, { duration: 300 });
```

### ❌ 错误：同时运行太多动画

**问题：**
```typescript
// BAD: Animating 50 items at once
items.forEach((item, index) => {
  Animated.timing(item.animation, {
    toValue: 1,
    duration: 300,
    useNativeDriver: true,
  }).start();
});
```

**影响：**
- 掉帧
- 性能卡顿
- 体验差

**✅ 修复：**
```typescript
// GOOD: Stagger animations
items.forEach((item, index) => {
  Animated.timing(item.animation, {
    toValue: 1,
    duration: 300,
    delay: index * 50, // Stagger by 50ms
    useNativeDriver: true,
  }).start();
});

// BETTER: Use layout animations
import { LayoutAnimation, Platform, UIManager } from 'react-native';

if (Platform.OS === 'android') {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
setItems(newItems); // Layout animates automatically
```

### 状态管理

### ❌ 错误：Prop Drilling

**问题：**
```typescript
// BAD: Passing props through 5 levels
<ParentComponent user={user}>
  <MiddleComponent user={user}>
    <AnotherComponent user={user}>
      <YetAnotherComponent user={user}>
        <FinalComponent user={user} />
      </YetAnotherComponent>
    </AnotherComponent>
  </MiddleComponent>
</ParentComponent>
```

**影响：**
- 难以维护
- 组件耦合
- 重构噩梦

**✅ 修复：**
```typescript
// GOOD: Context for shared state
const UserContext = createContext();

<UserContext.Provider value={user}>
  <ParentComponent>
    <MiddleComponent>
      <AnotherComponent>
        <YetAnotherComponent>
          <FinalComponent />
        </YetAnotherComponent>
      </AnotherComponent>
    </MiddleComponent>
  </ParentComponent>
</UserContext.Provider>

// In FinalComponent
const user = useContext(UserContext);
```

### ❌ 错误：把派生状态存进 state

**问题：**
```typescript
// BAD: Storing computed values in state
const [items, setItems] = useState([]);
const [filteredItems, setFilteredItems] = useState([]);

useEffect(() => {
  setFilteredItems(items.filter(item => item.active));
}, [items]);
```

**影响：**
- 状态同步问题
- 不必要的重渲染
- 维护代码更多

**✅ 修复：**
```typescript
// GOOD: Compute on render
const [items, setItems] = useState([]);
const filteredItems = useMemo(
  () => items.filter(item => item.active),
  [items]
);
```
