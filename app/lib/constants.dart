library;


const String kKeyPendingDistanceMeters = 'pending_distance_meters';
const String kKeyThemeMode = 'theme_mode';


const String kKeyTripMeters = 'trip_distance_meters';


const String kKeyDistanceBatchId = 'distance_batch_id';
const String kKeyDistanceBatchMeters = 'distance_batch_meters';


const String kKeyActivityCache = 'activity_cache_v1';



const double kMinDefectSpeedKmh = 20.0;


const double kBumpBaseThresholdMs2 = 7.0;


const double kBumpSpeedFactor = 0.12;



const double kSeverityMediumRatio = 2.0;
const double kSeverityHardRatio = 3.5;


const double kSeverityHard = 30.0;
const double kSeverityMedium = 20.0;


const double kSpeedBumpPulseM = 1.5;


const double kBrakedPulseM = 0.8;


const double kRoughRmsThresholdMs2 = 1.5;


const double kOdometerMinStepM = 0.6;


const double kOdometerMaxStepM = 300.0;


const double kOdometerMaxAccuracyM = 80.0;


const double kDistanceBatchBackgroundM = 25.0;


const double kMaxDistanceBatchM = 5000.0;


const double kActivityMidKm = 5.0;
const double kActivityHighKm = 20.0;
const int kActivityMidDefects = 3;
const int kActivityHighDefects = 8;