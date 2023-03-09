#!/bin/bash
set +e
set +x

proxyoff(){
    unset http_proxy
    unset https_proxy
    echo -e "[INFO] --- Proxy OFF!"
}

download_fd_model_zxvf() {
  local model="$1"  # xxx_model.tgz
  local len=${#model}
  local model_dir=${model:0:${#model}-4}  # xxx_model
  echo "${model_dir}"
  if [ ! -f "${model}" ]; then
     echo "[INFO] --- downloading $model"
     wget https://bj.bcebos.com/paddlehub/fastdeploy/$model && tar -zxvf $model
  else
     echo "[INFO] --- $model already exists!"
     if [ ! -d "${model_dir}" ]; then
        tar -zxvf $model
     else
        echo "[INFO] --- $model_dir already exists!"
     fi
  fi
}
download_fd_model_xvf() {
  local model="$1"
  local model_dir=${model:0:${#model}-4}  # xxx_model
  if [ ! -f "${model}" ]; then
     echo "[INFO] --- downloading $model"
     wget https://bj.bcebos.com/paddlehub/fastdeploy/$model && tar -xvf $model
  else
     echo "[INFO] --- $model already exists!"
     if [ ! -d "${model_dir}" ]; then
        tar -xvf $model
     else
        echo "[INFO] --- $model_dir already exists!"
     fi
  fi
}
download_common_model_zxvf() {
  local model_url="$1"
  local model="$2"
  local model_dir=${model:0:${#model}-4}  # xxx_model
  if [ ! -f "${model}" ]; then
     echo "[INFO] --- downloading $model"
     wget ${model_url} && tar -zxvf $model
  else
     echo "[INFO] --- $model already exists!"
     if [ ! -d "${model_dir}" ]; then
        tar -zxvf $model
     else
        echo "[INFO] --- $model_dir already exists!"
     fi
  fi
}
download_common_model_xvf() {
  local model_url="$1"
  local model="$2"
  local model_dir=${model:0:${#model}-4}  # xxx_model
  if [ ! -f "${model}" ]; then
     echo "[INFO] --- downloading $model"
     wget ${model_url} && tar -xvf $model
  else
     echo "[INFO] --- $model already exists!"
     if [ ! -d "${model_dir}" ]; then
        tar -xvf $model
     else
        echo "[INFO] --- $model_dir already exists!"
     fi
  fi
}
download_common_file() {
  local file_url="$1"
  local file="$2"
  if [ ! -f "${file}" ]; then
     echo "[INFO] --- downloading $file_url"
     wget ${file_url}
  else
     echo "[INFO] --- $file already exists!"
  fi
}

# Convert model: paddle -> onnx -> mnn/tnn/ncnn
CONVERT_LOG=convert.$(date "+%Y.%m.%d.%H.%M.%S").log
CONVERT_MODE=$2

dump_convert_log() {
   local info="$1"
   echo "$info" >> ${CONVERT_LOG}
   echo "$info"
}
check_or_delete() {
   if [ "$CONVERT_MODE" = "delete" ]; then
      if [ -f "$1" ]; then
         rm -f $1
         echo "[WARN][DELETE] $1 DELETED!"
         dump_convert_log "[WARN][DELETE] $1 DELETED!"
      fi
   fi
}
paddle2onnx_cmd() {
   local model_dir=$1
   local model_file=$2
   local param_file=$3
   local onnx_file=${model_file:0:${#model_file}-8}
   if [ ! -d "${model_dir}" ]; then
      echo "[ERROR] Can not found model dir: ${model_dir}, skip!"
      return 0
   fi
   if [ -f "$model_dir/$onnx_file.onnx" ]; then
      echo "[INFO] --- $model_dir/$onnx_file.onnx already exists!"
      dump_convert_log "[INFO][Paddle2ONNX][$model_dir][$onnx_file.onnx] Found!"
      check_or_delete $model_dir/$onnx_file.onnx
   else
      if [ "$CONVERT_MODE" = "delete" ]; then
         return
      fi
      echo "[INFO][$model_dir] --- running paddle2onnx_cmd ... "
      local ret=$(paddle2onnx --model_dir $model_dir --model_filename $model_file --params_filename $param_file --save_file $model_dir/$onnx_file.onnx) && echo $ret
      local check=$(echo $(echo $ret | grep exported | grep -v ERROR | wc -l))
      if [ "$check" = "1" ]; then
         dump_convert_log "[INFO][Paddle2ONNX][$model_dir] Success!"
         onnxsim $model_dir/$onnx_file.onnx $model_dir/$onnx_file.onnx
      else
         dump_convert_log "[INFO][Paddle2ONNX][$model_dir] Failed!"
      fi
   fi
}
onnx2mnn_cmd() {
   local model_dir=$1
   local onnx_file=$2
   local mnn_file=${onnx_file:0:${#onnx_file}-5}
   if [ ! -d "${model_dir}" ]; then
      echo "[ERROR] Can not found model dir: ${model_dir}, skip!"
      return 0
   fi
   if [ -f "$model_dir/$mnn_file.mnn" ]; then
      echo "[INFO] --- $model_dir/$mnn_file.mnn already exists!"
      dump_convert_log "[INFO][ONNX2MNN][$model_dir][$mnn_file.mnn] Found!"
      check_or_delete $model_dir/$mnn_file.mnn
   else
      if [ "$CONVERT_MODE" = "delete" ]; then
         return
      fi
      echo "[INFO][$model_dir] --- running onnx2mnn_cmd ... "
      local ret=$(MNNConvert -f ONNX --modelFile $model_dir/$onnx_file --MNNModel $model_dir/$mnn_file.mnn --bizCode biz) && echo $ret
      local check=$(echo $(echo $ret | grep Success | wc -l))
      if [ "$check" = "1" ]; then
         dump_convert_log "[INFO][ONNX2MNN][$model_dir] Success!"
      else
         dump_convert_log "[INFO][ONNX2MNN][$model_dir] Failed!"
      fi
   fi
}
onnx2tnn_cmd() {
   local model_dir=$1
   local onnx_file=$2
   local tnn_file=${onnx_file:0:${#onnx_file}-5}
   if [ ! -d "${model_dir}" ]; then
      echo "[ERROR] Can not found model dir: ${model_dir}, skip!"
      return 0
   fi
   if [ -f "$model_dir/$tnn_file.opt.tnnmodel" ]; then
      echo "[INFO] --- $model_dir/$tnn_file.opt.tnnmodel already exists!"
      dump_convert_log "[INFO][ONNX2TNN][$model_dir][$tnn_file.opt.tnnmodel] Found!"
      check_or_delete $model_dir/$tnn_file.opt.tnnmodel
      check_or_delete $model_dir/$tnn_file.opt.tnnproto
      check_or_delete $model_dir/$tnn_file.opt.onnx
   else
      if [ "$CONVERT_MODE" = "delete" ]; then
         return
      fi
      echo "[INFO][$model_dir] --- running onnx2tnn_cmd ... "
      # ${@:3} may look like: -in image:1,3,640,640 scale_factor:1,2
      # TNNConvert onnx2tnn $model_dir/$onnx_file -v=v1.0 -o $model_dir
      TNNConvert onnx2tnn $model_dir/$onnx_file -optimize -v=v1.0 -o $model_dir ${@:3} > onnx2tnn.log 2>&1 && cat onnx2tnn.log
      local check=$(echo $(cat onnx2tnn.log | grep succeed | wc -l))
      rm onnx2tnn.log
      if [ "$check" = "1" ]; then
         dump_convert_log "[INFO][ONNX2TNN][$model_dir] Success!"
      else
         dump_convert_log "[INFO][ONNX2TNN][$model_dir] Failed!"
      fi
   fi
}
onnx2ncnn_cmd() {
   local model_dir=$1
   local onnx_file=$2
   local ncnn_file=${onnx_file:0:${#onnx_file}-5}
   if [ ! -d "${model_dir}" ]; then
      echo "[ERROR] Can not found model dir: ${model_dir}, skip!"
      return 0
   fi
   if [ -f "$model_dir/$ncnn_file.opt.param" ]; then
      echo "[INFO] --- $model_dir/$ncnn_file.opt.param already exists!"
      dump_convert_log "[INFO][ONNX2NCNN][$model_dir][$ncnn_file.opt.param] Found!"
      check_or_delete $model_dir/$ncnn_file.opt.param
      check_or_delete $model_dir/$ncnn_file.opt.bin
      check_or_delete $model_dir/$ncnn_file.param
      check_or_delete $model_dir/$ncnn_file.bin
   else
      if [ "$CONVERT_MODE" = "delete" ]; then
         return
      fi
      echo "[INFO][$model_dir] --- running onnx2ncnn_cmd ... "
      onnx2ncnn $model_dir/$onnx_file $model_dir/$ncnn_file.param $model_dir/$ncnn_file.bin > onnx2ncnn.log 2>&1 && cat onnx2ncnn.log
      local check=$(echo $(cat onnx2ncnn.log | wc -l))
      rm onnx2ncnn.log
      if [ "$check" = "0" ]; then
         dump_convert_log "[INFO][ONNX2NCNN][$model_dir] Success!"
         ncnnoptimize $model_dir/$ncnn_file.param $model_dir/$ncnn_file.bin $model_dir/$ncnn_file.opt.param $model_dir/$ncnn_file.opt.bin 0
      else
         dump_convert_log "[INFO][ONNX2NCNN][$model_dir] Failed!"
         # remove cache
         rm -f $model_dir/$ncnn_file.bin
         rm -f $model_dir/$ncnn_file.param
      fi
   fi
}
convert_fd_model() {
   local model_dir=$1
   local model_file=$2
   local param_file=$3
   local onnx_file=${model_file:0:${#model_file}-8}.onnx
   paddle2onnx_cmd $model_dir $model_file $param_file
   onnx2mnn_cmd $model_dir $onnx_file
   onnx2tnn_cmd $model_dir $onnx_file ${@:4}
   onnx2ncnn_cmd $model_dir $onnx_file
}

proxyoff
# PaddleDetection
download_fd_model_zxvf ppyoloe_crn_l_300e_coco_no_nms.tgz
download_fd_model_zxvf picodet_l_640_coco_lcnet_no_nms.tgz
download_fd_model_zxvf ppyoloe_plus_crn_m_80e_coco_no_nms.tgz
download_fd_model_zxvf yolox_s_300e_coco_no_nms.tgz
download_fd_model_zxvf yolov5_s_300e_coco_no_nms.tgz
download_fd_model_zxvf yolov6_s_300e_coco_no_nms.tgz
download_fd_model_zxvf yolov7_l_300e_coco_no_nms.tgz
download_fd_model_zxvf yolov8_s_500e_coco_no_nms.tgz

# PaddleClas
download_fd_model_zxvf PPLCNet_x1_0_infer.tgz
download_fd_model_zxvf PPLCNetV2_base_infer.tgz
download_fd_model_zxvf MobileNetV1_x0_25_infer.tgz
download_fd_model_zxvf MobileNetV1_ssld_infer.tgz
download_fd_model_zxvf MobileNetV3_large_x1_0_ssld_infer.tgz
download_fd_model_zxvf ShuffleNetV2_x2_0_infer.tgz
download_fd_model_zxvf ResNet50_vd_infer.tgz
download_fd_model_zxvf EfficientNetB0_small_infer.tgz
download_fd_model_zxvf PPHGNet_tiny_ssld_infer.tgz

# PaddleSeg
download_fd_model_zxvf PP_LiteSeg_B_STDC2_cityscapes_with_argmax_infer.tgz
download_fd_model_zxvf PP_HumanSegV1_Lite_infer.tgz
download_fd_model_zxvf PP_HumanSegV2_Lite_192x192_with_argmax_infer.tgz
download_fd_model_zxvf Portrait_PP_HumanSegV2_Lite_256x144_with_argmax_infer.tgz
download_fd_model_zxvf Deeplabv3_ResNet101_OS8_cityscapes_with_argmax_infer.tgz
download_fd_model_zxvf SegFormer_B0-cityscapes-with-argmax.tgz
download_fd_model_xvf PP-Matting-512.tgz
download_fd_model_xvf PPHumanMatting.tgz
download_fd_model_xvf PPModnet_MobileNetV2.tgz

# PaddleOCR
download_common_model_xvf https://paddleocr.bj.bcebos.com/PP-OCRv3/chinese/ch_PP-OCRv3_det_infer.tar ch_PP-OCRv3_det_infer.tar
download_common_model_xvf https://paddleocr.bj.bcebos.com/PP-OCRv3/chinese/ch_PP-OCRv3_rec_infer.tar ch_PP-OCRv3_rec_infer.tar
download_common_model_xvf https://paddleocr.bj.bcebos.com/dygraph_v2.0/ch/ch_ppocr_mobile_v2.0_cls_infer.tar ch_ppocr_mobile_v2.0_cls_infer.tar
download_common_model_xvf https://paddleocr.bj.bcebos.com/PP-OCRv2/chinese/ch_PP-OCRv2_det_infer.tar ch_PP-OCRv2_det_infer.tar
download_common_model_xvf https://paddleocr.bj.bcebos.com/PP-OCRv2/chinese/ch_PP-OCRv2_rec_infer.tar ch_PP-OCRv2_rec_infer.tar

# download images
download_common_file https://bj.bcebos.com/paddlehub/fastdeploy/rec_img.jpg rec_img.jpg
download_common_file https://paddleseg.bj.bcebos.com/dygraph/demo/cityscapes_demo.png cityscapes_demo.png
download_common_file https://bj.bcebos.com/fastdeploy/test/portrait_heng.jpg portrait_heng.jpg
download_common_file https://bj.bcebos.com/paddlehub/fastdeploy/matting_input.jpg matting_input.jpg
download_common_file https://github.com/paddlepaddle/PaddleOCR/raw/release/2.6/doc/imgs/12.jpg 12.jpg
download_common_file https://github.com/paddlepaddle/PaddleClas/raw/release/2.4/deploy/images/ImageNet/ILSVRC2012_val_00000010.jpeg ILSVRC2012_val_00000010.jpeg
download_common_file https://github.com/paddlepaddle/PaddleDetection/raw/release/2.4/demo/000000014439.jpg 000000014439.jpg
download_common_file https://gitee.com/paddlepaddle/PaddleOCR/raw/release/2.6/ppocr/utils/ppocr_keys_v1.txt ppocr_keys_v1.txt

# covert models -> onnx/mnn/tnn/ncnn
if [ "$1" = "convert" ]; then
   convert_fd_model ppyoloe_crn_l_300e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model picodet_l_640_coco_lcnet_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640
   convert_fd_model ppyoloe_plus_crn_m_80e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model yolox_s_300e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model yolov5_s_300e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model yolov6_s_300e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model yolov7_l_300e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2
   convert_fd_model yolov8_s_500e_coco_no_nms model.pdmodel model.pdiparams -in image:1,3,640,640 scale_factor:1,2

   convert_fd_model PPLCNet_x1_0_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model PPLCNetV2_base_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model MobileNetV1_x0_25_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model MobileNetV1_ssld_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model MobileNetV3_large_x1_0_ssld_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model ShuffleNetV2_x2_0_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model ResNet50_vd_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model EfficientNetB0_small_infer inference.pdmodel inference.pdiparams -in 1,3,224,224
   convert_fd_model PPHGNet_tiny_ssld_infer inference.pdmodel inference.pdiparams -in 1,3,224,224

   convert_fd_model PP_LiteSeg_B_STDC2_cityscapes_with_argmax_infer model.pdmodel model.pdiparams -in 1,3,512,512
   convert_fd_model PP_HumanSegV1_Lite_infer model.pdmodel model.pdiparams -in 1,3,192,192
   convert_fd_model PP_HumanSegV2_Lite_192x192_with_argmax_infer model.pdmodel model.pdiparams -in 1,3,192,192
   convert_fd_model Portrait_PP_HumanSegV2_Lite_256x144_with_argmax_infer model.pdmodel model.pdiparams -in 1,3,144,256
   convert_fd_model Deeplabv3_ResNet101_OS8_cityscapes_with_argmax_infer model.pdmodel model.pdiparams -in 1,3,512,512
   convert_fd_model SegFormer_B0-cityscapes-with-argmax model.pdmodel model.pdiparams -in 1,3,512,512
   convert_fd_model PPHumanMatting model.pdmodel model.pdiparams
   convert_fd_model PPModnet_MobileNetV2 model.pdmodel model.pdiparams -in 1,3,512,512

   convert_fd_model ch_PP-OCRv3_det_infer inference.pdmodel inference.pdiparams -in x:1,3,960,608
   convert_fd_model ch_PP-OCRv3_rec_infer inference.pdmodel inference.pdiparams -in x:1,3,48,572
   convert_fd_model ch_ppocr_mobile_v2.0_cls_infer inference.pdmodel inference.pdiparams -in x:1,3,48,572
   convert_fd_model ch_PP-OCRv2_det_infer inference.pdmodel inference.pdiparams -in x:1,3,960,608
   convert_fd_model ch_PP-OCRv2_rec_infer inference.pdmodel inference.pdiparams -in x:1,3,48,572

   echo "-----------------------------------------Convert Status-----------------------------------------"
   cat ${CONVERT_LOG}
   echo "------------------------------------------------------------------------------------------------"
   echo "Saved -> ${CONVERT_LOG}"
fi

# ./get_models.sh
# ./get_models.sh convert
# ./get_models.sh convert delete
