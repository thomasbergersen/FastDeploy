// Copyright (c) 2023 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "flags.h"
#include "macros.h"
#include "option.h"

namespace vision = fastdeploy::vision;
namespace benchmark = fastdeploy::benchmark;

DEFINE_bool(no_nms, false, "Whether the model contains nms.");
DEFINE_bool(quant, false, "Whether to use quantize model");

int main(int argc, char* argv[]) {
#if defined(ENABLE_BENCHMARK) && defined(ENABLE_VISION)
  // Initialization
  auto option = fastdeploy::RuntimeOption();
  if (!CreateRuntimeOption(&option, argc, argv, true)) {
    return -1;
  }
  auto im = cv::imread(FLAGS_image);
  std::unordered_map<std::string, std::string> config_info;
  benchmark::ResultManager::LoadBenchmarkConfig(FLAGS_config_path,
                                                &config_info);
  std::string model_name, params_name, config_name;
  auto model_format = fastdeploy::ModelFormat::PADDLE;
  if (!UpdateModelResourceName(&model_name, &params_name, &config_name,
                               &model_format, config_info, true, FLAGS_quant)) {
    return -1;
  }

  auto model_file = FLAGS_model + sep + model_name;
  auto params_file = FLAGS_model + sep + params_name;
  auto config_file = FLAGS_model + sep + config_name;
  option.mnn_option.in_orders = {{"image", 0}, {"scale_factor", 1}};
  option.mnn_option.out_orders = {{"tmp_73", 0}, {"concat_15.tmp_0", 1}};
  option.tnn_option.in_orders = {{"image", 0}, {"scale_factor", 1}};
  option.tnn_option.out_orders = {{"tmp_73", 0}, {"concat_15.tmp_0", 1}};
  option.ncnn_option.in_orders = {{"image", 0}, {"scale_factor", 1}};
  option.ncnn_option.out_orders = {{"tmp_73", 0}, {"concat_15.tmp_0", 1}};
  auto model_ppyolov8 = vision::detection::PaddleYOLOv8(
      model_file, params_file, config_file, option, model_format);
  if (FLAGS_no_nms) {
    model_ppyolov8.GetPostprocessor().ApplyNMS();
  }
  vision::DetectionResult res;
  if (config_info["precision_compare"] == "true") {
    // Run once at least
    model_ppyolov8.Predict(im, &res);
    // 1. Test result diff
    std::cout << "=============== Test result diff =================\n";
    // Save result to -> disk.
    std::string det_result_path = "ppyolov8_result.txt";
    benchmark::ResultManager::SaveDetectionResult(res, det_result_path);
    // Load result from <- disk.
    vision::DetectionResult res_loaded;
    benchmark::ResultManager::LoadDetectionResult(&res_loaded, det_result_path);
    // Calculate diff between two results.
    auto det_diff =
        benchmark::ResultManager::CalculateDiffStatis(res, res_loaded);
    std::cout << "Boxes diff: mean=" << det_diff.boxes.mean
              << ", max=" << det_diff.boxes.max
              << ", min=" << det_diff.boxes.min << std::endl;
    std::cout << "Label_ids diff: mean=" << det_diff.labels.mean
              << ", max=" << det_diff.labels.max
              << ", min=" << det_diff.labels.min << std::endl;
    // 2. Test tensor diff
    std::cout << "=============== Test tensor diff =================\n";
    std::vector<vision::DetectionResult> batch_res;
    std::vector<fastdeploy::FDTensor> input_tensors, output_tensors;
    std::vector<cv::Mat> imgs;
    imgs.push_back(im);
    std::vector<vision::FDMat> fd_images = vision::WrapMat(imgs);

    model_ppyolov8.GetPreprocessor().Run(&fd_images, &input_tensors);
    input_tensors[0].name = "image";
    input_tensors[1].name = "scale_factor";
    input_tensors[2].name = "im_shape";
    input_tensors.pop_back();
    model_ppyolov8.Infer(input_tensors, &output_tensors);
    model_ppyolov8.GetPostprocessor().Run(output_tensors, &batch_res);
    // Save tensor to -> disk.
    auto& tensor_dump = output_tensors[0];
    std::string det_tensor_path = "ppyolov8_tensor.txt";
    benchmark::ResultManager::SaveFDTensor(tensor_dump, det_tensor_path);
    // Load tensor from <- disk.
    fastdeploy::FDTensor tensor_loaded;
    benchmark::ResultManager::LoadFDTensor(&tensor_loaded, det_tensor_path);
    // Calculate diff between two tensors.
    auto det_tensor_diff = benchmark::ResultManager::CalculateDiffStatis(
        tensor_dump, tensor_loaded);
    std::cout << "Tensor diff: mean=" << det_tensor_diff.data.mean
              << ", max=" << det_tensor_diff.data.max
              << ", min=" << det_tensor_diff.data.min << std::endl;
  }
  // Run profiling
  BENCHMARK_MODEL(model_ppyolov8, model_ppyolov8.Predict(im, &res))
  auto vis_im = vision::VisDetection(im, res);
  cv::imwrite("vis_result.jpg", vis_im);
  std::cout << "Visualized result saved in ./vis_result.jpg" << std::endl;
#endif
  return 0;
}
